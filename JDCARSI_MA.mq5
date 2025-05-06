//+------------------------------------------------------------------+
//|            DCA_RSI_MA_Trim_v3.mq5                                |
//|   DCA with RSI/MA, TP always, SL after MaxOrders, Trim logic     |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>
CTrade trade;

input int    RSI_Period = 14;
input int    MA_Period = 20;
input double StepUSD = 20.0;
input double SL_Range = 30.0;
input double TP_Range = 30.0;
input double TrimThreshold = 5.0;
input int    MaxOrders = 3;
input double LotSize = 0.01;

double last_dca_buy_price = 0.0;
double last_dca_sell_price = 0.0;

struct PositionInfo {
   ulong ticket;
   double price;
   double volume;
};

int OnInit() {
   Print("✅ EA DCA + RSI/MA + Trim logic initialized.");
   return(INIT_SUCCEEDED);
}

void ModifyEachPosition(PositionInfo &positions[], int count, double avg_price, bool isBuy, bool set_sl) {
   int stopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double stopDistance = stopLevel * _Point;
   double marketPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = isBuy ? avg_price - SL_Range : avg_price + SL_Range;
   double tp = isBuy ? avg_price + TP_Range : avg_price - TP_Range;

   if (MathAbs(marketPrice - tp) >= stopDistance) {
      for (int i = 0; i < count; i++) {
         double curr_sl = set_sl ? sl : 0.0;
         trade.PositionModify(positions[i].ticket, curr_sl, tp);
      }
   }
}

void TrimOneIfNeeded(PositionInfo &positions[], int &count, double avg_price, bool isBuy, double &last_dca_price) {
   double marketPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool shouldTrim = isBuy ? (marketPrice > avg_price + TrimThreshold)
                           : (marketPrice < avg_price - TrimThreshold);

   if (!shouldTrim || count <= 1)
      return;

   ulong far_ticket = 0;
   double far_diff = -1;
   int far_index = -1;

   for (int i = 0; i < count; i++) {
      double diff = positions[i].price - avg_price;
      if ((isBuy && diff < 0) || (!isBuy && diff > 0)) {
         double abs_diff = MathAbs(diff);
         if (abs_diff > far_diff) {
            far_diff = abs_diff;
            far_ticket = positions[i].ticket;
            far_index = i;
         }
      }
   }

   if (far_ticket > 0 && trade.PositionClose(far_ticket)) {
      Print("✂️ Trimmed ", (isBuy ? "BUY" : "SELL"), " ticket: ", far_ticket);
      for (int i = far_index; i < count - 1; i++) {
         positions[i] = positions[i + 1];
      }
      count--;
      if (count > 0)
         last_dca_price = positions[count - 1].price;
   }
}

void OnTick() {
   static int rsi_handle = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);
   static int ma_handle  = iMA(_Symbol, _Period, MA_Period, 0, MODE_SMA, PRICE_CLOSE);

   double rsi_buffer[1], ma_buffer[2];
   if (CopyBuffer(rsi_handle, 0, 0, 1, rsi_buffer) <= 0 ||
       CopyBuffer(ma_handle, 0, 0, 2, ma_buffer) <= 0)
       return;

   double rsi = rsi_buffer[0];
   double ma_now = ma_buffer[0];
   double ma_prev = ma_buffer[1];
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   int buy_count = 0, sell_count = 0;
   double buy_total = 0, buy_volume = 0;
   double sell_total = 0, sell_volume = 0;
   double buy_avg = 0, sell_avg = 0;

   PositionInfo buy_positions[3];
   PositionInfo sell_positions[3];

   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double vol = PositionGetDouble(POSITION_VOLUME);
      double p = PositionGetDouble(POSITION_PRICE_OPEN);

      if (type == POSITION_TYPE_BUY) {
         buy_total += p * vol;
         buy_volume += vol;
         buy_positions[buy_count].ticket = ticket;
         buy_positions[buy_count].price = p;
         buy_positions[buy_count].volume = vol;
         buy_count++;
      } else if (type == POSITION_TYPE_SELL) {
         sell_total += p * vol;
         sell_volume += vol;
         sell_positions[sell_count].ticket = ticket;
         sell_positions[sell_count].price = p;
         sell_positions[sell_count].volume = vol;
         sell_count++;
      }
   }

   buy_avg = (buy_volume > 0) ? buy_total / buy_volume : 0;
   sell_avg = (sell_volume > 0) ? sell_total / sell_volume : 0;

   // BUY logic
   if (buy_count == 0) {
      if (rsi < 30 && ma_now > ma_prev) {
         double sl = 0.0; // không đặt SL ban đầu
         double tp = ask + TP_Range;
         if (trade.Buy(LotSize, _Symbol, ask, sl, tp, "BUY_1")) {
            last_dca_buy_price = ask;
            Print("✅ BUY_1 opened at ", ask, " | RSI=", rsi, " MA=", ma_now);
         }
      }
   } else if (buy_count < MaxOrders && ask <= last_dca_buy_price - StepUSD) {
      double sl = 0.0;
      double tp = ask + TP_Range;
      if (trade.Buy(LotSize, _Symbol, ask, sl, tp, "BUY_DCA")) {
         last_dca_buy_price = ask;
         Print("📉 BUY_DCA opened at ", ask);
      }
   }

   // SELL logic
   if (sell_count == 0) {
      if (rsi > 70 && ma_now < ma_prev) {
         double sl = 0.0;
         double tp = bid - TP_Range;
         if (trade.Sell(LotSize, _Symbol, bid, sl, tp, "SELL_1")) {
            last_dca_sell_price = bid;
            Print("✅ SELL_1 opened at ", bid, " | RSI=", rsi, " MA=", ma_now);
         }
      }
   } else if (sell_count < MaxOrders && bid >= last_dca_sell_price + StepUSD) {
      double sl = 0.0;
      double tp = bid - TP_Range;
      if (trade.Sell(LotSize, _Symbol, bid, sl, tp, "SELL_DCA")) {
         last_dca_sell_price = bid;
         Print("📈 SELL_DCA opened at ", bid);
      }
   }

   // BUY Management
   if (buy_count == MaxOrders) {
      ModifyEachPosition(buy_positions, buy_count, buy_avg, true, true);
      TrimOneIfNeeded(buy_positions, buy_count, buy_avg, true, last_dca_buy_price);
      ModifyEachPosition(buy_positions, buy_count, buy_avg, true, true);
   } else {
      ModifyEachPosition(buy_positions, buy_count, buy_avg, true, false);
   }

   // SELL Management
   if (sell_count == MaxOrders) {
      ModifyEachPosition(sell_positions, sell_count, sell_avg, false, true);
      TrimOneIfNeeded(sell_positions, sell_count, sell_avg, false, last_dca_sell_price);
      ModifyEachPosition(sell_positions, sell_count, sell_avg, false, true);
   } else {
      ModifyEachPosition(sell_positions, sell_count, sell_avg, false, false);
   }
}

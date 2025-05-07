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
   Print("✅ EA DCA + Trim-to-One + Accurate DCA initialized.");
   return(INIT_SUCCEEDED);
}

void ModifyEachPosition(PositionInfo &positions[], int count, double avg_price, bool isBuy, bool setSL) {
   int stopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double stopDistance = stopLevel * _Point;
   double marketPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = isBuy ? avg_price - SL_Range : avg_price + SL_Range;
   double tp = isBuy ? avg_price + TP_Range : avg_price - TP_Range;

   if (MathAbs(marketPrice - tp) >= stopDistance) {
      for (int i = 0; i < count; i++) {
         double actual_sl = setSL ? sl : 0.0;
         trade.PositionModify(positions[i].ticket, actual_sl, tp);
      }
   }
}

void TrimAllButOneIfNeeded(PositionInfo &positions[], int &count, double avg_price, bool isBuy, double &last_dca_price) {
   if (count <= 1) return;

   double marketPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool shouldTrim = isBuy ? (marketPrice > avg_price + TrimThreshold)
                           : (marketPrice < avg_price - TrimThreshold);
   if (!shouldTrim) return;

   int closest_index = 0;
   double min_diff = DBL_MAX;
   for (int i = 0; i < count; i++) {
      double diff = MathAbs(positions[i].price - avg_price);
      if (diff < min_diff) {
         min_diff = diff;
         closest_index = i;
      }
   }

   for (int i = 0; i < count; i++) {
      if (i == closest_index) continue;
      if (trade.PositionClose(positions[i].ticket)) {
         Print("✂️ Trimmed ", (isBuy ? "BUY" : "SELL"), " ticket: ", positions[i].ticket);
      }
   }

   positions[0] = positions[closest_index];
   count = 1;
   last_dca_price = positions[0].price;
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

   // === BUY Management (Trim trước)
   bool buy_full = (buy_count == MaxOrders);
   ModifyEachPosition(buy_positions, buy_count, buy_avg, true, buy_full);
   if (buy_count > 1) {
      TrimAllButOneIfNeeded(buy_positions, buy_count, buy_avg, true, last_dca_buy_price);
      bool buy_full_after_trim = (buy_count == MaxOrders);
      ModifyEachPosition(buy_positions, buy_count, buy_avg, true, buy_full_after_trim);
   }

   // === SELL Management (Trim trước)
   bool sell_full = (sell_count == MaxOrders);
   ModifyEachPosition(sell_positions, sell_count, sell_avg, false, sell_full);
   if (sell_count > 1) {
      TrimAllButOneIfNeeded(sell_positions, sell_count, sell_avg, false, last_dca_sell_price);
      bool sell_full_after_trim = (sell_count == MaxOrders);
      ModifyEachPosition(sell_positions, sell_count, sell_avg, false, sell_full_after_trim);
   }

   // === BUY Entry
   if (buy_count == 0) {
      if (rsi < 30 && ma_now > ma_prev) {
         double sl = 0.0;
         double tp = ask + TP_Range;
         if (trade.Buy(LotSize, _Symbol, ask, sl, tp, "BUY_1")) {
            last_dca_buy_price = ask;
            Print("✅ BUY_1 opened at ", ask);
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

   // === SELL Entry
   if (sell_count == 0) {
      if (rsi > 70 && ma_now < ma_prev) {
         double sl = 0.0;
         double tp = bid - TP_Range;
         if (trade.Sell(LotSize, _Symbol, bid, sl, tp, "SELL_1")) {
            last_dca_sell_price = bid;
            Print("✅ SELL_1 opened at ", bid);
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
}

//+------------------------------------------------------------------+
//| Expert Advisor Template for EUR/USD                             |
//| Timeframe H4, EMA Trend, RSI Confirmation, Auto SL/TP            |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

// Create trade object
CTrade trade;

// Input parameters
input double Lots            = 0.05;     // Fixed Lot Size
input int    EMA_Fast_Period = 50;        // Fast EMA period
input int    EMA_Slow_Period = 200;       // Slow EMA period
input int    RSI_Period      = 14;        // RSI Period
input int    SL_Pips         = 50;        // Stop Loss in Pips
input int    TP_Pips         = 100;       // Take Profit in Pips

// Global Handles
int handleEMA_Fast;
int handleEMA_Slow;
int handleRSI;

//+------------------------------------------------------------------+
int OnInit()
  {
   handleEMA_Fast = iMA(Symbol(), PERIOD_H4, EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Slow = iMA(Symbol(), PERIOD_H4, EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI      = iRSI(Symbol(), PERIOD_H4, RSI_Period, PRICE_CLOSE);

   if(handleEMA_Fast==INVALID_HANDLE || handleEMA_Slow==INVALID_HANDLE || handleRSI==INVALID_HANDLE)
     {
      Print("Error creating indicators!");
      return INIT_FAILED;
     }
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(Period()!=PERIOD_H4) return;

   // Count current open positions for this symbol
   int total_positions = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == Symbol())
            total_positions++;
        }
     }

   if(total_positions >= 3)
      return; // No more than 3 positions allowed

   double emaFast[], emaSlow[], rsiVal[];

   if( CopyBuffer(handleEMA_Fast, 0, 1, 1, emaFast)<=0 ||
       CopyBuffer(handleEMA_Slow, 0, 1, 1, emaSlow)<=0 ||
       CopyBuffer(handleRSI, 0, 1, 1, rsiVal)<=0 )
     {
      Print("Error copying indicator buffers!");
      return;
     }

   double Ask = NormalizeDouble(SymbolInfoDouble(Symbol(), SYMBOL_ASK), _Digits);
   double Bid = NormalizeDouble(SymbolInfoDouble(Symbol(), SYMBOL_BID), _Digits);
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);

   if(emaFast[0] > emaSlow[0] && rsiVal[0] < 30)
     {
      double SL = Ask - SL_Pips * point * 10;
      double TP = Ask + TP_Pips * point * 10;
      trade.SetDeviationInPoints(20);
      trade.Buy(Lots, Symbol(), Ask, SL, TP, "Buy Order");
     }

   if(emaFast[0] < emaSlow[0] && rsiVal[0] > 70)
     {
      double SL = Bid + SL_Pips * point * 10;
      double TP = Bid - TP_Pips * point * 10;
      trade.SetDeviationInPoints(20);
      trade.Sell(Lots, Symbol(), Bid, SL, TP, "Sell Order");
     }
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(handleEMA_Fast);
   IndicatorRelease(handleEMA_Slow);
   IndicatorRelease(handleRSI);
  }
//+------------------------------------------------------------------+

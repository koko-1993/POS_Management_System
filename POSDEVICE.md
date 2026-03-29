Bluetooth printer ကို mobile POS နဲ့ချိတ်သုံးမယ်ဆိုရင် production မတင်ခင် ကြိုကာထားတာ လိုပါတယ်။

အဓိကကြိုပြင်သင့်တာတွေက:
- `printer state check` ထည့်ပါ။ ချိတ်ထားလား, paper out လား, powered off လား မစစ်ဘဲ print မလွှတ်ပါနဲ့။
- `retry + timeout` ထည့်ပါ။ connect တစ်ခါမရရင် 1-2 ကြိမ်ပြန်စမ်းပြီး အကြာကြီး hang မနေရအောင် timeout လုပ်ပါ။
- `idempotent print job` လုပ်ပါ။ button နှိပ်နှစ်ခါဖြစ်လို့ slip နှစ်စောင်မထွက်အောင် `print_job_id` နဲ့ duplicate guard ထားပါ။
- `queued printing` လုပ်ပါ။ order save ပြီးမှ print queue ထဲထည့်ပါ။ printer fail လည်း sale data မပျောက်ရပါ။
- `reprint list` ထားပါ။ print မရရင် later reprint လုပ်နိုင်အောင် recent receipts archive ကနေ ပြန်ထုတ်လို့ရရမယ်။
- `clear error UI` ပြပါ။ “Bluetooth off”, “Printer disconnected”, “Paper out”, “Print failed, tap to retry” လို message တိတိကျကျပြရမယ်။
- `fallback` ထားပါ။ Bluetooth printer မရရင် PDF/preview/save/share option တစ်ခုရှိရင် support လုပ်ရလွယ်တယ်။
- `format safety` လုပ်ပါ။ printer width 58mm/80mm မတူတာ, Myanmar font/encoding မကိုက်တာ, long item names wrap ပျက်တာကို handle လုပ်ရမယ်။
- `connection recovery` လုပ်ပါ။ app background/foreground ပြောင်းချိန် reconnect logic လိုတတ်တယ်။
- `audit log` သိမ်းပါ။ ဘယ် invoice ကို print success/fail ဖြစ်လဲ log ရှိရင် debugging အရမ်းလွယ်တယ်။

အထူးသတိထားရမယ့် bug တွေက:
- print button နှိပ်ပြီး spinner ပဲပြနေတယ်
- invoice save မဖြစ်ဘဲ print ပဲထွက်သွားတယ်
- bluetooth reconnect မလုပ်နိုင်တော့ဘူး
- တစ်စောင်ကို နှစ်ခါသုံးခါထွက်တယ်
- Myanmar text လွဲ/ကွဲ/မပေါ်ဘူး
- printer model မတူလို့ command set မကိုက်ဘူး

အကောင်းဆုံး flow က:
1. order ကို local/server မှာ save
2. receipt archive ထဲသိမ်း
3. print job queue ထဲထည့်
4. printer ready ဖြစ်ရင် print
5. success/fail status update
6. fail ရင် retry / reprint list ထဲကျန်

Next step အနေနဲ့ Bluetooth printing အတွက် `print queue + retry + reprint` architecture ကို app ထဲထည့်လို့ရပါတယ်။

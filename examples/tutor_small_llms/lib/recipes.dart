// Prompts and inputs for the guides (the ones the tutorial's tables
// were measured with).

class Recipes {
  static const expenseSystem = r'''
Extract one expense record from an Italian documento commerciale (Agenzia delle Entrate RT / Fatture e Corrispettivi layout). Camera OCR is noisy: 0/O swaps, extra headers, VAT lines, card last-4, document numbers.

Reply with this JSON object only — no markdown, no extra keys:
{"merchant": string, "total": number, "currency": "EUR", "date_printed": string}

merchant — the shop's legal or trade name (the company line, often above DOCUMENTO COMMERCIALE). Not P.I. / P.IVA, not DOC, not the street, not a line-item name, not the card last-4.
total — the amount actually paid for the purchase. Dot decimal. Not di cui IVA, not one line item, not the cash tendered, not the change given.
currency — EUR on Italian fiscal tickets.
date_printed — copy the date exactly as printed on the ticket, character for character. Do not reformat it, do not fix OCR, do not guess a year.''';

  static const expenseShotUser = r'''
AP0THEKE AM BAHNH0F
LINIENSTR. 4O  BERLIN
Ibuprofen 400mg N20        8,49
SUMME EUR                  8,49
EC ****8812
03.11.25  17:22
BON-NR 004821''';

  static const expenseShotAssistant = r'{"merchant":"APOTHEKE AM BAHNHOF","total":8.49,"currency":"EUR","date_printed":"03.11.25"}';

  static const starbucksOcr = r'''
STARBUCKS COFFEE ITALY S.R.L.
ROMA TERMINI - VIA GIOBERTI
P.I. 01234560966

DOCUMENTO COMMERCIALE
di vendita o prestazione

DESCRIZIONE              IVA   Prezzo(€)
Cappuccin0            2  10%     7,00
Cornetto              1  10%     1,80
Subtotale                        8,80
TOTALE COMPLESSIVO               8,80
di cui IVA                       0,80
Pagamento elettronico            8,80
CARTA ****4521

14/O8/2026  08:41
DOC N. 0001234''';

  static const tabaccheriaOcr = r'''
TABACCHERIA IL FARO DI ROSSI G. & C. S.A.S.
VIA APPIA NUOVA 214 - ROMA
P.IVA 09876540158

DOCUMENTO COMMERCIALE
di vendita o prestazione

DESCRIZIONE              IVA   Prezzo(€)
Acqua naturale 0,5L   1  10%     1,00
Panin0 crudo          1  10%     4,50
Caffe espresso        2  10%     2,20

TOTALE COMPLESSIVO               7,70
di cui IVA                       0,70
CONTANTI                        10,00
REST0                            2,30

02-09-2026  O7:55
DOC N. 0000456''';

  static const calendarSystem = r'''
Read a chat thread and report the meeting they agreed on. Do not compute dates and do not convert anything.

Reply with this JSON object only — no markdown, no extra keys:
{"title": string, "day_said": string, "start_said": string, "end_said": string or null, "location": string or null}

title — short Title Case name: the activity plus who. Not small talk from earlier lines. Not a sentence.
day_said — copy the day exactly as the thread says it: "14/08", "tomorrow", "friday". Do not turn it into a date.
start_said — the agreed start time as they wrote it, 24-hour clock. If they revised it, use the time they settled on.
end_said — the time someone said they have to leave, or null if nobody said.
location — the place they named, or null.''';

  static const calendarShotUser = r'''
Ana Kovac: coffee tue 19/08 10:30 at the station? i leave 11:00
You: yes''';

  static const calendarShotAssistant = r'{"title":"Coffee With Ana","day_said":"19/08","start_said":"10:30","end_said":"11:00","location":"the station"}';

  static const marcoExport = r'''
[13/08/2026, 12:04:11] Marco Rossi: yo u around fri
[13/08/2026, 12:05:03] You: yeah till sat
[13/08/2026, 12:07:44] Marco Rossi: lunch 14/08 13:00 at the termini place? i gotta run 14:30 so dont be late
[13/08/2026, 12:08:02] You: ok see you there''';

  static const calendarWhenSystem = r'''
Today is Thursday 13 August 2026. You already know this date.

A meeting is often split across several chat bubbles: one bubble names the day (tomorrow, in 3 days, friday, 14/08), a later bubble names a time, a later bubble may change that time, a later bubble may name the place. Glue the day they said to the last clock they agreed. Do not convert a relative day to a calendar date — Swift will.

Reply with this JSON object only — no markdown, no extra keys:
{"title": string, "when": string, "location": string or null}

title — short Title Case: the activity plus who. Not small talk.
when — one string: the day they said, a space, then the 24-hour clock they settled on. Both parts are required. Forms:
  tomorrow HH:mm
  in N days HH:mm
  in N weeks HH:mm
  in N months HH:mm
  dd/mm HH:mm
"tomorrow" with no clock is incomplete. A clock with no day is incomplete. If they offered 10:00 then said make it 10:30, write 10:30.
location — the place they named, or null.''';

  static const List<(String, String)> calendarWhenShots = [];

  static const lenaRevised = r'''
Lena Fischer: still on for the climbing gym tomorrow?
You: yes! 18:00?
Lena Fischer: make it 18:30, standing desk meeting runs late
You: 18:30 works, see you at Boulderwelt''';

  static const lockerSystem = r'''
Read a parcel pickup notification and return the pickup code only. One token — no sentence, no quotes.

The pickup code is the short number the recipient types at the locker or shows at the counter. It is not the tracking or consignment number, not the order number, not the opening hours, not a phone number. Copy it exactly, including any hyphen.''';

  static const lockerShotUser = r'''
Ihre Sendung 00340434123456789016 liegt in der DHL Packstation 139, Berlin Hbf. Ihr Abholcode: 4482. Geöffnet 06:00-22:00.''';

  static const lockerShotAssistant = r'4482';

  static const smsAmazon = r'''
Your package with 1 item is ready to be picked up from Amazon Hub Locker - Roma Termini (Via Giolitti).

Your pickup code is 482917

Use this code to pick up your package. Locker hours: 06:00-23:00.
Order #204-8471932-5510237''';

  static const smsInpost = r'''
InPost: paczka 620148329041 czeka w Paczkomacie KRA01M, ul. Długa 12.
Kod odbioru: 730114. Odbierz do 20.08.''';

  static const smsRoyalmail = r'''
Royal Mail: your parcel RM938271645GB is at Camden Post Office.
Bring this collection PIN: 61529 and photo ID. Open Mon-Sat 09:00-17:30.''';

  static const smsBring = r'''
Bring: pakken din (tracking 70712345678901) ligger klar i skapet på Storo.
Hentekode 4471-88. Hentes innen 7 dager.''';

  static const routerSystem = r'''
Classify one share-sheet paste into exactly one label. Reply with that label only — no sentence, no punctuation.

receipt — a fiscal receipt / documento commerciale / Kassenbon (shop name, IVA, TOTALE).
event — a chat thread that agrees a meeting time.
locker — a carrier or parcel pickup notice (PIN / pickup code / Abholcode / kod odbioru).
other — none of the above.

Classify the document type, not a polite wrapper.''';

  static const routerShotReceipt = r'''
DOCUMENTO COMMERCIALE
TOTALE COMPLESSIVO    12,50
P.I. 01234560966''';

  static const routerShotEvent = r'''
[12/08/2026, 18:02:11] Ana Kovac: coffee thu 10:30 at the station?
[12/08/2026, 18:03:01] You: yes''';

}

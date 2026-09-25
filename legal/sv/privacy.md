# Integritetspolicy

Version 2026-09-26

[COMPANY NAME], [ADDRESS], org.nr [CVR/VAT NO.], är **personuppgiftsansvarig** för de personuppgifter som behandlas i EasySesh. Kontakt: [PRIVACY EMAIL].

## Vad vi samlar in
- **Kontouppgifter:** e-post, lösenord (lagras krypterat hos vår inloggningsleverantör), roll (artist/studio), inloggningsmetod (e-post, Apple, Google).
- **Profiluppgifter:** artistnamn, genrer, stad, bio, bild, länkar. För studior: studiouppgifter, adress, kontaktuppgifter, bilder, priser, öppettider.
- **Bokningsuppgifter:** bokningar, tider, anteckningar till studion, avbokningar, tvister.
- **Betalningsuppgifter:** belopp, betalningsstatus, kvitton samt kortmärke och de 4 sista siffrorna. Kortnummer hanteras av Stripe och sparas aldrig av EasySesh. För utbetalningar till studior hanteras bankuppgifter och identitetskontroller av Stripe Connect.
- **Meddelanden** mellan artister och studior samt **recensioner** och **anmälningar**.
- **Enhetsuppgifter:** token för pushaviseringar, appversion.
- **Plats:** bara när du använder appen och bara om du tillåter det. Den används på din enhet för att visa studior och avstånd i närheten och **sparas inte** på våra servrar.
- **Incheckning:** om du checkar in vid ankomst sparar vi tiden och, om du tillåter plats, hur långt från studion du var (inte dina koordinater). Det används som bevis om det uppstår en tvist om en session.
- **Betyg:** betyg som studior ger artister och artister ger studior, och eventuella invändningar.
- **Modereringsuppgifter:** varningar, avstängningar och porteringar med anledning och period.
- **Samtyckesregister:** vilken version av dessa dokument du godkände och när.

## Varför vi använder dem (rättslig grund, GDPR art. 6)
- För att tillhandahålla tjänsten: konton, bokningar, betalningar, meddelanden och support. Grund: **avtal** (art. 6.1 b).
- Betalningar, fakturering och bokföring. Grund: **rättslig förpliktelse** (art. 6.1 c).
- Säkerhet, bedrägeribekämpning, moderering av anmält innehåll och upprätthållande av våra villkor. Grund: **berättigat intresse** (art. 6.1 f).
- Pushaviseringar om bokningar och meddelanden: **avtal**. Du kan stänga av varje typ i Inställningar.
- Nyheter och erbjudanden: bara med ditt **samtycke** (art. 6.1 a), som du när som helst kan återkalla i Inställningar.

## Vem vi delar dem med
- **Motparten i din bokning.** Studior ser artistens namn, profil och bokningsuppgifter; artister ser studions offentliga annons (inklusive adress) och bokningsuppgifter.
- **Personuppgiftsbiträden:** Supabase (databas, inloggning, lagring; EU-region [REGION]), Stripe (betalningar och utbetalningar), Apple (Logga in med Apple, pushaviseringar), Google (Google-inloggning) och vår e-postleverantör [PROVIDER].
- **Myndigheter**, när lagen kräver det.

Vi säljer inte personuppgifter. När uppgifter överförs utanför EU/EES förlitar vi oss på EU-kommissionens beslut om adekvat skyddsnivå (t.ex. EU–US Data Privacy Framework) eller standardavtalsklausuler.

## Hur länge vi sparar dem
- **Konto- och profiluppgifter:** så länge ditt konto finns. De raderas eller anonymiseras när du raderar kontot.
- **Boknings-, betalnings- och fakturauppgifter:** 5 år från räkenskapsårets slut, enligt bokföringslagen ([t.ex. dansk bokföringslag § 10 / grekisk lag 4308/2014]).
- **Meddelanden:** så länge kontot finns. De anonymiseras vid radering men sparas om de behövs för en pågående tvist.
- **Anmälningar och modereringsuppgifter:** upp till 2 år.

## Dina rättigheter
Du har rätt till tillgång, rättelse, radering, begränsning av behandling, invändning och dataportabilitet. Du kan:
- **Ladda ner dina uppgifter:** Inställningar → Dina uppgifter → Ladda ner mina uppgifter.
- **Radera ditt konto:** Inställningar → Radera konto.
- För allt annat, mejla [PRIVACY EMAIL]. Vi svarar inom en månad.

Du kan klaga hos din dataskyddsmyndighet, t.ex. IMY (www.imy.se), Datatilsynet (Danmark, www.datatilsynet.dk) eller den grekiska myndigheten (www.dpa.gr).

## Säkerhet
Uppgifter krypteras vid överföring (TLS) och i lagring. Åtkomsten begränsas per roll och upprätthålls av databasen (row-level security). Administratörskonton kräver tvåfaktorsautentisering. Kortuppgifter hanteras bara av Stripe, som är PCI-DSS-certifierat.

## Barn
EasySesh riktar sig inte till barn under 13 år, och användare under 18 år behöver tillstånd från förälder eller vårdnadshavare.

## Ändringar
Vi meddelar dig i appen om väsentliga ändringar av denna policy och ber dig läsa och godkänna den uppdaterade versionen innan du fortsätter.

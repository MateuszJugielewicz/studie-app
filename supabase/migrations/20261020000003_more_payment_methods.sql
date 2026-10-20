-- Payments go through Stripe's payment sheet with every method turned on in the Stripe dashboard
-- (Settings → Payment methods): cards, Apple Pay, Google Pay, Link, PayPal, Klarna, MobilePay,
-- iDEAL, Bancontact, BLIK, EPS, Revolut Pay, … The booking and the receipt say which one was used;
-- anything not listed here is saved as 'other' with Stripe's name for it in card_brand.
alter type public.payment_method add value if not exists 'link';
alter type public.payment_method add value if not exists 'paypal';
alter type public.payment_method add value if not exists 'klarna';
alter type public.payment_method add value if not exists 'mobilepay';
alter type public.payment_method add value if not exists 'ideal';
alter type public.payment_method add value if not exists 'bancontact';
alter type public.payment_method add value if not exists 'blik';
alter type public.payment_method add value if not exists 'eps';
alter type public.payment_method add value if not exists 'revolut_pay';
alter type public.payment_method add value if not exists 'other';

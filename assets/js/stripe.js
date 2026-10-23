// Stripe.js loads on every page so Radar sees the whole visit, but only once
// the page is idle (app.js), so it never holds up LiveView connecting. A payment
// form asks for it straight away. One script tag, however often it's asked for.
let loading = null;

export function loadStripe() {
  loading ??= new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = "https://js.stripe.com/v3/";
    script.onload = () => resolve(window.Stripe);
    script.onerror = () => {
      // Lets a payment form opened later try again.
      loading = null;
      script.remove();
      reject(new Error("Stripe.js failed to load"));
    };
    document.head.append(script);
  });
  return loading;
}

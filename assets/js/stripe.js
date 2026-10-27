// Stripe.js loads only when a payment form mounts, so browsing the store sets no
// Stripe cookies (privacy policy). One script tag, however often it's asked for.
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

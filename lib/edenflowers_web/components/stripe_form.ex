defmodule EdenflowersWeb.StripeForm do
  @moduledoc """
  The payment form, with the Stripe Payment Element, that checkout, course
  sign-ups, payment links and the subscription card share.
  """
  use EdenflowersWeb, :html

  @doc """
  Renders the form the `Stripe` hook mounts its payment element into.

  The hook finds the element, error message and button by id, so a page
  holds at most one. `mode="setup"` saves a card without charging it.

  The Payment Element starts before the PaymentIntent or SetupIntent exists.
  The page creates it in its submit event and sends the client secret with
  `stripe:process_payment`, so Apple Pay opens inside the customer's tap.
  """
  attr :id, :string, required: true
  attr :mode, :string, default: "payment", values: ["payment", "setup"]
  attr :amount, :integer, default: nil, doc: "in cents, shown on wallet sheets; required in payment mode"

  attr :setup_future_usage, :string,
    default: nil,
    doc: ~s|"off_session" when the PaymentIntent created on paying saves the card|

  attr :customer_session_client_secret, :string, default: nil, doc: "shows the signed-in customer's saved cards"
  attr :return_path, :string, required: true, doc: "where Stripe sends the customer back to, on the host they paid from"
  attr :billing_name, :string, default: nil
  attr :billing_email, :string, default: nil
  attr :billing_phone, :string, default: nil
  attr :on_loading, JS, default: %JS{}, doc: "runs as Stripe starts working, alongside disabling the button"
  attr :on_ready, JS, default: %JS{}, doc: "runs as Stripe settles, alongside re-enabling the button"
  attr :rest, :global
  slot :before_button
  slot :inner_block, required: true, doc: "the button label"

  def stripe_form(assigns) do
    ~H"""
    <form
      id={@id}
      phx-hook=".Stripe"
      data-mode={@mode}
      data-amount={@amount}
      data-setup-future-usage={@setup_future_usage}
      data-customer-session-client-secret={@customer_session_client_secret}
      data-publishable-key={Application.get_env(:edenflowers, :stripe_publishable_key)}
      data-return-path={@return_path}
      data-billing-name={@billing_name}
      data-billing-email={@billing_email}
      data-billing-phone={@billing_phone}
      data-stripe-loading={JS.set_attribute(@on_loading, {"disabled", "true"}, to: "#payment-button")}
      data-stripe-ready={JS.remove_attribute(@on_ready, "disabled", to: "#payment-button")}
      class="flex flex-col gap-4"
      {@rest}
    >
      <div phx-update="ignore" id="payment-element"></div>
      <p phx-update="ignore" id="stripe-error-message" role="alert" class="text-error"></p>

      {render_slot(@before_button)}

      <.form_button disabled={true} id="payment-button">
        {render_slot(@inner_block)}
      </.form_button>
    </form>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Stripe">
      import { loadStripe } from "@/js/stripe";

      export default {
        async mounted() {
          const returnPath = this.el.getAttribute("data-return-path");
          if (!returnPath) {
            return this.logAndPushError("data-return-path attribute is missing.");
          }
          this.returnUrl = new URL(returnPath, window.location.origin).href;

          // data-mode="setup" saves a card without charging it.
          this.mode = this.el.dataset.mode;
          this.amount = Number(this.el.dataset.amount);
          if (this.mode === "payment" && !this.amount) {
            return this.logAndPushError("data-amount attribute is missing.");
          }
          this.setupFutureUsage = this.el.dataset.setupFutureUsage;

          this.publishableKey = this.el.getAttribute("data-publishable-key");
          if (!this.publishableKey) {
            return this.logAndPushError("data-publishable-key attribute is missing.");
          }

          this.stripeReadyJS = this.el.getAttribute("data-stripe-ready");
          if (!this.stripeReadyJS) {
            return this.logAndPushError("data-stripe-ready attribute is missing.");
          }

          this.stripeLoadingJS = this.el.getAttribute("data-stripe-loading");
          if (!this.stripeLoadingJS) {
            return this.logAndPushError("data-stripe-loading attribute is missing.");
          }

          this.stripeErrorMessage = document.getElementById("stripe-error-message");
          if (!this.stripeErrorMessage) {
            return this.logAndPushError("#stripe-error-message element not found.");
          }

          this.button = document.getElementById("payment-button");
          if (!this.button) {
            return this.logAndPushError("#payment-button element not found.");
          }

          this.paymentElement = document.getElementById("payment-element");
          if (!this.paymentElement) {
            return this.logAndPushError("#payment-element element not found.");
          }

          try {
            const Stripe = await loadStripe();
            const stripe = Stripe(this.publishableKey);
            const elements = (this.elements = stripe.elements({
              ...this.intentOptions(),
              customerSessionClientSecret:
                this.el.dataset.customerSessionClientSecret || undefined,
              appearance: this.buildAppearance(),
              // Stripe has no "sv-FI", so pass the bare language ("en", "sv", "fi").
              locale: document.documentElement.lang.split(/[-_]/)[0],
              // Stripe runs in a cross-origin iframe and can't see the host's
              // @font-face rules, so Open Sans must be loaded inside the iframe.
              // Self-hosted rather than Google Fonts, which would send customers' IPs to Google.
              fonts: [
                {
                  family: "Open Sans",
                  src: `url(${new URL("/fonts/OpenSans-Variable.woff2", window.location.origin)}) format("woff2")`,
                  weight: "300 800",
                },
              ],
            }));

            const paymentElement = elements.create("payment", {
              paymentMethodOrder: ["mobilepay", "card"],
              defaultValues: {
                billingDetails: {
                  name: this.el.dataset.billingName,
                  email: this.el.dataset.billingEmail,
                  phone: this.el.dataset.billingPhone,
                },
              },
            });
            paymentElement.mount("#payment-element");
            paymentElement.on("ready", (event) => {
              this.stripeReady();
            });
            paymentElement.on("loaderror", (event) => {
              this.logAndPushError("payment element failed to load", event.error);
            });

            // The server couldn't create the PaymentIntent, so Stripe never started.
            this.handleEvent("stripe:ready", () => this.stripeReady());

            // Safari only opens the Apple Pay sheet inside the tap, so wallets are
            // collected here, before "pay" makes its round trip to the server.
            this.el.addEventListener("submit", () => {
              this.submitted = elements.submit();
            });

            this.handleEvent("stripe:process_payment", async ({ client_secret }) => {
              this.stripeLoading();
              this.stripeErrorMessage.textContent = ""; // Clear previous errors

              const { error: submitError } = await this.submitted;
              if (submitError) {
                return this.handleStripeError(
                  submitError,
                  "error collecting payment details",
                );
              }

              const confirm =
                this.mode === "setup" ? stripe.confirmSetup : stripe.confirmPayment;
              const { error } = await confirm.call(stripe, {
                elements,
                clientSecret: client_secret,
                confirmParams: {
                  return_url: this.returnUrl,
                },
              });

              if (error) {
                this.handleStripeError(error, "error confirming payment");
              }

              // On success Stripe redirects to return_url.
            });
          } catch (error) {
            const message =
              "Failed to initialize payment form. Please try again later.";
            this.logAndPushError(message, error);
            this.stripeReady(); // Re-enable button if initialization fails
          }
        },

        // Switching between one-off and subscription changes card saving and the
        // CustomerSession, and Elements can't swap a CustomerSession in place.
        // ponytail: reloads the page rather than rebuilding Elements in place.
        updated() {
          if (this.el.dataset.setupFutureUsage !== this.setupFutureUsage) {
            return window.location.reload();
          }

          // Apple Pay and Google Pay show this amount on their sheets.
          const amount = Number(this.el.dataset.amount);
          if (this.mode === "payment" && amount !== this.amount) {
            this.amount = amount;
            // Elements doesn't exist until Stripe.js loads; it then starts with this amount.
            this.elements?.update({ amount });
          }
        },

        // Elements starts before the PaymentIntent or SetupIntent exists, and must
        // match what the server creates when the customer pays. One that saves a
        // card for later charges takes only cards.
        intentOptions() {
          if (this.mode === "setup") {
            return { mode: "setup", currency: "eur", paymentMethodTypes: ["card"] };
          }

          const options = { mode: "payment", amount: this.amount, currency: "eur" };
          if (this.setupFutureUsage) {
            options.setupFutureUsage = this.setupFutureUsage;
            options.paymentMethodTypes = ["card"];
          }
          return options;
        },

        // The Payment Element shows validation errors itself, but not a declined
        // card; Stripe's card_error message is written for the customer.
        handleStripeError(error, message) {
          if (error.type === "card_error") {
            this.stripeErrorMessage.textContent = error.message;
          } else if (error.type !== "validation_error") {
            this.logAndPushError(message, error);
          }

          this.stripeReady(); // Re-enable button after payment error
        },

        /**
         * Logs an error message and pushes a 'stripe:error' event to the server.
         * @param {string} message - The error message.
         * @param {object | null} [errorObject=null] - The original error object, if available.
         */
        logAndPushError(message, errorObject = null) {
          const msg = `Stripe Hook Error: ${message}`;
          console.error(msg, errorObject || "");
          this.pushEvent("stripe:error", {
            message: msg,
            details: errorObject || "",
          });
        },

        stripeReady() {
          this.button.removeAttribute("aria-busy");
          this.liveSocket.execJS(this.el, this.stripeReadyJS);
        },

        // The form's .phx-submit-loading ends when the server acks "pay", but
        // confirmPayment (and any 3DS challenge) runs long after, so the button
        // carries its own busy state to keep the spinner up until Stripe settles.
        stripeLoading() {
          this.button.setAttribute("aria-busy", "true");
          this.liveSocket.execJS(this.el, this.stripeLoadingJS);
        },

        /**
         * Build a Stripe Elements `appearance` config from the live daisyUI theme
         * tokens on `:root`, so the Payment Element matches our `<input class="input
         * input-lg">` styling. Stripe Elements run in an iframe and can't be styled
         * with CSS, so we resolve the values up-front and pass them in.
         *
         * daisyUI input model (mirrored here):
         *   - rest: border-color = color-mix(base-content 20%, transparent)
         *   - focus / focus-within: border-color flips to full base-content;
         *                           outline 2px solid with 2px offset, in primary --
         *                           daisyUI draws that outline in base-content, base.css
         *                           overrides every focus ring to the brand green
         *   - invalid: border-color and focus outline flip to --color-error
         *   - input-lg: 48px tall, 18px font, 12px horizontal padding
         *
         * The payment-method tabs mirror the `radio-card` input instead: base-300
         * frame, primary frame over a 5% primary wash once selected.
         */
        buildAppearance() {
          const css = getComputedStyle(document.documentElement);
          const v = (name, fallback = "") =>
            css.getPropertyValue(name).trim() || fallback;

          // Stripe's colour variables only accept hex, rgb() or hsl() and silently
          // drop our oklch() tokens, so paint each one to a canvas pixel to get sRGB.
          const ctx = document
            .createElement("canvas")
            .getContext("2d", { willReadFrequently: true });
          const rgb = (name) => {
            ctx.fillStyle = v(name);
            ctx.fillRect(0, 0, 1, 1);
            const [r, g, b] = ctx.getImageData(0, 0, 1, 1).data;
            return `rgb(${r}, ${g}, ${b})`;
          };

          const baseContent = rgb("--color-base-content");
          const base100 = rgb("--color-base-100");
          const primary = rgb("--color-primary");
          const error = rgb("--color-error");
          const base300 = rgb("--color-base-300");

          const subtleBorder = `color-mix(in oklab, ${baseContent} 20%, transparent)`;
          // Checkboxes carry a heavier hairline than inputs -- see `.checkbox` in forms.css.
          const checkboxBorder = `color-mix(in oklab, ${baseContent} 55%, transparent)`;

          return {
            theme: "flat",
            variables: {
              colorPrimary: primary,
              colorBackground: base100,
              colorText: baseContent,
              colorDanger: error,
              fontFamily: v("--font-sans", "system-ui, sans-serif"),
              // 16px is the host body baseline; per-element sizes are set in `rules`.
              fontSizeBase: "16px",
              borderRadius: v("--radius-field", "0.25rem"),
              spacingUnit: "4px",
              // Our form stacks fields with `space-y-6`.
              gridRowSpacing: "24px",
            },
            rules: {
              ".Input": {
                backgroundColor: base100,
                border: `1px solid ${subtleBorder}`,
                boxShadow: "none",
                fontSize: "18px",
                fontWeight: "400",
                lineHeight: "27px",
                // Stripe's inputs are border-box: 2 × 9.5px + 27px line-height + 2px border = 48px (input-lg).
                padding: "9.5px 12px",
              },
              ".Input::placeholder": {
                color: `color-mix(in oklab, ${baseContent} 50%, transparent)`,
              },
              ".Input:focus": {
                backgroundColor: base100,
                border: `1px solid ${baseContent}`,
                outline: `2px solid ${primary}`,
                outlineOffset: "2px",
                boxShadow: "none",
              },
              ".Input--invalid": {
                backgroundColor: base100,
                border: `1px solid ${error}`,
                boxShadow: "none",
                // Stripe tints invalid text with colorDanger; `.input-error` only reddens the frame.
                color: baseContent,
              },
              ".Input--invalid:focus": {
                backgroundColor: base100,
                border: `1px solid ${error}`,
                outline: `2px solid ${error}`,
                outlineOffset: "2px",
                boxShadow: "none",
              },
              ".Label": {
                color: baseContent,
                fontFamily: v("--font-sans", "system-ui, sans-serif"),
                fontSize: "16px",
                fontWeight: "400",
                lineHeight: "24px",
                marginBottom: "4px",
              },
              ".Tab": {
                backgroundColor: base100,
                border: `1px solid ${base300}`,
                boxShadow: "none",
                color: baseContent,
              },
              ".Tab:hover": {
                backgroundColor: base100,
                border: `1px solid ${primary}`,
                boxShadow: "none",
                color: baseContent,
              },
              ".Tab--selected": {
                backgroundColor: `color-mix(in oklab, ${primary} 5%, ${base100})`,
                border: `1px solid ${primary}`,
                boxShadow: "none",
                color: baseContent,
              },
              ".Tab--selected:focus": {
                backgroundColor: `color-mix(in oklab, ${primary} 5%, ${base100})`,
                border: `1px solid ${primary}`,
                outline: `2px solid ${primary}`,
                outlineOffset: "2px",
                boxShadow: "none",
                color: baseContent,
              },
              // The flat theme fills a selected tab with colorPrimary and lightens its
              // label and icon to match; our tint is light, so they stay dark.
              ".TabLabel--selected": {
                color: baseContent,
              },
              ".TabIcon--selected": {
                fill: baseContent,
              },
              // Matches the recurring-charge note below it (`text-sm leading-relaxed text-base-content/80`).
              ".TermsText": {
                color: `color-mix(in oklab, ${baseContent} 80%, transparent)`,
                fontSize: "14px",
                fontWeight: "400",
                lineHeight: "22.75px",
              },
              ".CheckboxInput": {
                backgroundColor: base100,
                border: `1px solid ${checkboxBorder}`,
                borderRadius: "0",
                boxShadow: "none",
              },
              ".CheckboxInput--checked": {
                backgroundColor: primary,
                border: `1px solid ${primary}`,
                borderRadius: "0",
                boxShadow: "none",
              },
              ".Error": {
                color: error,
                fontFamily: v("--font-sans", "system-ui, sans-serif"),
                fontSize: "14px",
                fontWeight: "400",
                lineHeight: "20px",
                marginTop: "6px",
              },
            },
          };
        },
      };
    </script>
    """
  end
end

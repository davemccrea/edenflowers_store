defmodule EdenflowersWeb.Store.GiftVoucherLive do
  @moduledoc """
  The Gift voucher checkout: what the voucher is for and who it's from, then
  card payment, on one page. It never touches the browser's cart, so flowers
  and a voucher are paid for separately.
  """

  use EdenflowersWeb, :live_view

  require Logger
  import EdenflowersWeb.StripeForm, only: [stripe_form: 1]
  import EdenflowersWeb.VoucherSkeleton, only: [voucher_skeleton: 1]

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Format
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.Payments.GiftVoucherPdf
  alias Edenflowers.Payments.GiftVoucherStyle

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @default_amount 50
  # Picked by eye: even snow that keeps clear of the amount and the name.
  @first_snow_seed 148_922

  @impl true
  def mount(_params, _session, socket) do
    sale = Orders.get_resumable_gift_voucher_sale!(socket.assigns.visitor_id, actor: socket.assigns.current_user)

    {:ok,
     socket
     |> assign(
       page_title: ~t"Gift voucher",
       alternates: alternates("/#{language}/gift-voucher"),
       page_description:
         ~t"An Eden Flowers gift voucher, from 20 to 200 €, to spend on flowers, subscriptions and courses in Vaasa.",
       locale: Format.locale(),
       sale: sale && load_sale(sale),
       editing?: sale != nil,
       voucher_styles: online_voucher_styles(),
       # Until the buyer touches the form, the preview shows where their message goes.
       interacted?: sale != nil,
       preview: nil,
       preview_error?: false,
       previewed: nil
     )
     |> assign_form()
     |> render_preview()}
  end

  # Keep payment in browser history so Back returns to the editable voucher.
  # A reload or reconnect resumes this browser's sale; a URL alone can't open one.
  @impl true
  def handle_params(%{"step" => "payment"}, _uri, %{assigns: %{sale: nil}} = socket) do
    {:noreply, push_patch(socket, to: ~q"/#{language}/gift-voucher", replace: true)}
  end

  def handle_params(%{"step" => "payment"}, _uri, socket) do
    {:noreply, socket |> assign(editing?: false) |> render_preview()}
  end

  def handle_params(_params, _uri, %{assigns: %{sale: sale, editing?: false}} = socket) when not is_nil(sale) do
    {:noreply, socket |> assign(editing?: true) |> assign_form() |> render_preview()}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <style :type={EdenflowersWeb.ColocatedCSS}>
      #voucher-preview {
        transition: transform 120ms ease-out;
      }

      #voucher-preview:has(.voucher-shuffle:active) {
        transform: scale(0.98);
      }

      @media (prefers-reduced-motion: reduce) {
        #voucher-preview:has(.voucher-shuffle:active) {
          transform: none;
        }
      }

      /* Reserve space for the voucher without covering the form.
         Short screens keep the full preview in normal flow instead. */
      .voucher-form-fields fieldset {
        /* Scrolling to an error can reveal the shy header, so reserve its full height. */
        scroll-margin-top: calc(
          var(--header-height) + var(--spacing) * 4 + env(safe-area-inset-top)
        );
      }

      @media (width < 64rem) and (height >= 40rem) {
        .voucher-form-fields {
          --voucher-preview-height: min(calc((100vw - 2rem) * 148 / 210), 32svh);
        }

        .voucher-form-fields:has(
            #voucher-preview-band:not([data-keyboard-open]):not([data-field-too-tall])
          )
          fieldset {
          scroll-margin-top: calc(var(--voucher-preview-height) + 6rem);
        }

        #voucher-preview-band {
          position: sticky;
          top: 0;
          padding-top: env(safe-area-inset-top);
          /* The 2rem fade and 1rem field clearance need more than the grid's
             2.5rem gap, or the correction scroll pulls the preview off its stop. */
          margin-bottom: 0.5rem;
        }

        #voucher-preview-band > .voucher-preview {
          max-width: calc(var(--voucher-preview-height) * 210 / 148);
          margin-inline: auto;
        }

        #voucher-preview-band::after {
          content: "";
          position: absolute;
          inset-inline: 0;
          top: 100%;
          height: 2rem;
          background: linear-gradient(var(--color-base-100), transparent);
          pointer-events: none;
        }

        #voucher-preview-band:is([data-keyboard-open], [data-field-too-tall]) {
          position: relative;
        }

        #voucher-preview-band:is([data-keyboard-open], [data-field-too-tall])::after {
          display: none;
        }

        /* Hide the header while typing too, so it can't flash behind the preview
           between keyboard dismissal and the preview taking over the top. */
        body:has(
            #voucher-preview-band:is([data-keyboard-open], [data-preview-owns-top])
          )
          #hotfx-shy-header {
          visibility: hidden;
          opacity: 0;
          pointer-events: none;
          transition: none;
        }
      }
    </style>

    <Layouts.app
      current_user={@current_user}
      order={@order}
      flash={@flash}
      current_path={@current_path}
      notice_bar={@notice_bar}
      alternates={@alternates}
    >
      <.container>
        <header class="max-w-prose">
          <h1 class="page-title">{~t"Give a gift voucher"} <span aria-hidden="true">💛</span></h1>
          <p class="mt-6 text-lg leading-relaxed">
            {~t"Let them choose their own flowers, a flower subscription or a place on one of my courses. They can use it online or in my shop at Minimossen."}
          </p>
        </header>

        <div class="mt-10" data-testid="gift-voucher-checkout">
          <.form
            :if={is_nil(@sale) || @editing?}
            id="gift-voucher-form"
            for={@form}
            data-warn-unsaved={~t"You have unsaved changes. Leave without saving?"}
            phx-change="validate"
            phx-submit="continue"
          >
            <%!-- The mobile preview leaves room for the form, and scrolls normally on short
                 screens or while the keyboard obscures the viewport. --%>
            <div class="voucher-form-fields grid gap-10 lg:grid-cols-2 lg:items-start lg:gap-x-16">
              <fieldset class="flex flex-col lg:col-start-1 lg:row-start-1">
                <legend class="eyebrow text-base-content/70 mb-5">{~t"Make it personal"}</legend>
                <%!-- Equal-height choices keep wrapped Finnish and Swedish labels aligned. --%>
                <div class="[&_fieldset>div]:grid [&_fieldset>div]:auto-rows-fr [&_fieldset>div]:grid-cols-2">
                  <.input
                    :let={option}
                    label={~t"Style"}
                    field={@form[:voucher_style]}
                    type="radio-card"
                    options={Enum.map(@voucher_styles, &style_option/1)}
                  >
                    {option.label}
                    <span :if={option[:emoji]} aria-hidden="true">{option.emoji}</span>
                  </.input>
                </div>
              </fieldset>

              <div
                id="voucher-preview-band"
                phx-hook="VoucherPreview"
                class="bg-base-100 z-60 relative -mx-4 min-w-0 px-4 py-3 lg:top-[calc(var(--shy-header-offset,0px)+2rem)] lg:sticky lg:z-auto lg:col-start-2 lg:row-span-4 lg:row-start-1 lg:mx-0 lg:bg-transparent lg:px-0 lg:py-0"
              >
                <.voucher_preview
                  preview={@preview}
                  loading?={@preview_loading?}
                  error?={@preview_error?}
                  shuffle?={GiftVoucherStyle.christmas?(@form[:voucher_style].value)}
                />
                <.input field={@form[:voucher_snow_seed]} type="hidden" />
              </div>

              <div class="flex flex-col gap-6 lg:col-start-1 lg:row-start-2 lg:-mt-4">
                <.input
                  label={~t"Who is it for?"}
                  field={@form[:recipient_name]}
                  type="text"
                  autocomplete="off"
                  phx-debounce="blur"
                  required
                />
                <.input
                  label={~t"Your message"}
                  field={@form[:card_message]}
                  type="textarea"
                  maxlength={Order.Checkout.voucher_message_length()}
                  help={~t"Up to #{count = Order.Checkout.voucher_message_length()} characters."}
                  phx-debounce="blur"
                  rows="3"
                />
              </div>

              <fieldset class="flex flex-col lg:col-start-1 lg:row-start-3">
                <legend class="eyebrow text-base-content/70 mb-5">{~t"Voucher"}</legend>
                <div class="grid gap-6 sm:grid-cols-2">
                  <.input
                    label={~t"Amount"}
                    field={@form[:amount]}
                    type="select"
                    options={Enum.map(Order.Checkout.voucher_amounts(), &{Format.storefront_price(&1, @locale), &1})}
                  />
                  <.input
                    label={~t"Voucher language"}
                    field={@form[:voucher_locale]}
                    type="select"
                    options={[{"Svenska", "sv-FI"}, {"Suomi", "fi"}, {"English", "en-GB"}]}
                  />
                </div>
              </fieldset>

              <fieldset class="flex flex-col lg:col-start-1 lg:row-start-4">
                <legend class="eyebrow text-base-content/70 mb-5">{~t"Your details"}</legend>
                <div class="grid gap-6 sm:grid-cols-2">
                  <.input
                    label={~t"Your name"}
                    field={@form[:customer_name]}
                    type="text"
                    autocomplete="name"
                    phx-debounce="400"
                    required
                  />
                  <.input
                    label={~t"Your email"}
                    field={@form[:customer_email]}
                    type="email"
                    autocomplete="email"
                    phx-debounce="400"
                    required
                  />
                  <.button
                    type="submit"
                    variant="primary"
                    size="lg"
                    class="w-full sm:col-span-2"
                    data-testid="continue-to-payment"
                  >
                    {~t"Continue to payment"}
                  </.button>
                  <p class="text-base-content/70 -mt-3 text-sm sm:col-span-2">
                    {~t"You'll receive an email with a PDF, to print or forward on. The voucher is valid for a year from the day you buy it."}
                    <.link navigate={~q"/#{language}/terms" <> "#gift-vouchers"} class="link-underline-static-body">
                      {~t"See Gift voucher terms"}</.link>.
                  </p>
                  <button
                    :if={@interacted?}
                    type="button"
                    phx-click="start_over"
                    data-confirm={~t"Clear everything you've entered and start over?"}
                    class="link-underline-hover text-base-content/70 justify-self-start py-2.5 text-sm sm:col-span-2"
                  >
                    {~t"Start over"}
                  </button>
                </div>
              </fieldset>
            </div>
          </.form>

          <%!-- The preview comes first, so it's above the payment on a phone; on a wide
               screen it moves to the right of it. --%>
          <div
            :if={@sale && !@editing?}
            id="gift-voucher-payment"
            phx-hook=".VoucherPayment"
            class="grid gap-8 lg:grid-cols-2 lg:items-start lg:gap-x-16"
          >
            <div class="min-w-0 lg:col-start-2 lg:row-start-1">
              <.voucher_preview preview={@preview} loading?={@preview_loading?} error?={@preview_error?} />
            </div>
            <section aria-labelledby="pay-heading" data-testid="payment-section">
              <%!-- The form, and the button that submitted it, are gone: focus lands here instead of on <body>. --%>
              <h2
                id="pay-heading"
                tabindex="-1"
                class="section-title mb-4 focus-visible:outline-none"
              >
                {~t"Payment"}
              </h2>
              <p>
                {~t"Gift voucher of #{amount = Format.storefront_price(@sale.grand_total, @locale)} for #{name = @sale.recipient_name}"}
              </p>
              <button type="button" phx-click="change" class="link-underline-hover text-base-content/70 mb-6 block py-2.5">
                {~t"Change"}
              </button>

              <.stripe_form
                id="gift-voucher-payment-form"
                phx-submit="pay"
                amount={StripeAPI.to_stripe_amount(@sale.grand_total)}
                return_path={~p"/checkout/complete/#{@sale.id}"}
                billing_name={@sale.customer_name}
                billing_email={@sale.customer_email}
              >
                {~t"Pay"} {Format.currency(@sale.grand_total, @locale)}
              </.stripe_form>
            </section>
          </div>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".VoucherPayment">
            export default {
              mounted() {
                this.frame = requestAnimationFrame(() => {
                  // Focus announces Payment without scrolling past the preview on phones.
                  this.el.querySelector("#pay-heading").focus({ preventScroll: true });
                  // Scrolling up reveals the fixed header, including any shop notice.
                  const headerHeight =
                    document.getElementById("hotfx-shy-header")?.offsetHeight ?? 0;
                  this.el.style.scrollMarginTop = `${headerHeight}px`;
                  this.el.scrollIntoView({
                    block: "start",
                    behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches
                      ? "instant"
                      : "smooth",
                  });
                });
              },
              destroyed() {
                cancelAnimationFrame(this.frame);
              },
            };
          </script>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  defp online_voucher_styles do
    Edenflowers.Fulfillment.get_shop_calendar!(authorize?: false)
    |> Ash.load!(:online_voucher_styles, authorize?: false)
    |> Map.fetch!(:online_voucher_styles)
  end

  defp style_option(:cream), do: %{value: "cream", label: ~t"Signature"}
  defp style_option(:christmas), do: %{value: "christmas", label: ~t"Christmas red", emoji: "🎁"}
  defp style_option(:christmas_green), do: %{value: "christmas_green", label: ~t"Christmas green", emoji: "🎄"}

  attr :preview, :string, required: true
  attr :loading?, :boolean, required: true
  attr :error?, :boolean, required: true
  attr :shuffle?, :boolean, default: false

  # Sized before the image arrives, so the fields beside it don't jump.
  defp voucher_preview(assigns) do
    ~H"""
    <div class="voucher-preview">
      <div
        id="voucher-preview"
        class={["bg-base-100 relative shadow-sm lg:shadow-lg", !@error? && "aspect-[210/148]"]}
        aria-busy={to_string(@loading?)}
      >
        <.voucher_skeleton :if={!@preview && !@error?} />
        <p
          :if={@loading? && !@error?}
          class="sr-only"
          role="status"
        >
          {~t"Loading preview…"}
        </p>
        <img
          :if={@preview && !@error?}
          id="voucher-preview-image"
          phx-hook=".PreviewCrossfade"
          src={"data:image/png;base64," <> @preview}
          alt={~t"Preview of your gift voucher"}
          class="block h-full w-full"
          data-testid="voucher-preview"
        />
        <img
          :if={@preview && !@error?}
          id="voucher-preview-previous"
          phx-update="ignore"
          alt=""
          class="pointer-events-none absolute inset-0 h-full w-full opacity-0"
        />
        <script :type={Phoenix.LiveView.ColocatedHook} name=".PreviewCrossfade">
          /**
           * When a snow shuffle's preview arrives, the old one is laid over it in
           * #voucher-preview-previous and fades out, so the snow resettles instead of
           * cutting. Other changes (style, fields) still swap at once. That img is
           * phx-update="ignore", so patches leave the opacity and src set here alone.
           */
          export default {
            mounted() {
              this.onClick = (event) => {
                if (event.target.closest(".voucher-shuffle")) this.shuffled = true;
              };
              this.container = this.el.parentElement;
              this.container.addEventListener("click", this.onClick);
            },

            destroyed() {
              this.container.removeEventListener("click", this.onClick);
            },

            beforeUpdate() {
              this.previousSrc = this.el.src;
            },

            async updated() {
              const previous = document.getElementById("voucher-preview-previous");
              if (!previous || this.el.src === this.previousSrc) return;
              if (!this.shuffled) return;
              this.shuffled = false;
              if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;

              previous.getAnimations().forEach((animation) => animation.cancel());
              previous.src = this.previousSrc;

              // Held at full opacity until the new image can paint, then faded out.
              const fade = previous.animate([{ opacity: 1 }, { opacity: 0 }], {
                duration: 220,
                easing: "ease-out",
                fill: "both",
              });
              fade.pause();

              await this.el.decode().catch(() => {});
              // A quicker shuffle cancelled this fade and started its own.
              if (fade.playState === "idle") return;
              fade.play();
            },
          };
        </script>
        <button
          :if={@shuffle? && !@error?}
          type="button"
          phx-click={JS.push("shuffle_snow", loading: "#gift-voucher-form")}
          aria-label={~t"Shuffle the snow on the voucher"}
          class="voucher-shuffle absolute inset-0 cursor-pointer"
          data-testid="shuffle-snow"
        ></button>
        <div
          :if={@error?}
          class="flex flex-col items-center justify-center gap-3 p-4 text-center"
          role="status"
        >
          <p>{~t"The preview couldn't load. Please try again."}</p>
          <button type="button" phx-click="retry_preview" class="link-underline-hover min-h-11 px-3">
            {~t"Retry preview"}
          </button>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply,
     socket
     |> assign(form: AshPhoenix.Form.validate(socket.assigns.form, params), interacted?: true)
     |> render_preview()}
  end

  def handle_event("continue", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, sale} ->
        {:noreply,
         socket
         |> assign(sale: load_sale(sale), editing?: false)
         |> render_preview()
         |> push_patch(to: ~q"/#{language}/gift-voucher?step=payment")
         |> EdenflowersWeb.Analytics.track("Gift voucher checkout started", %{}, once: "gift-voucher:#{sale.id}")}

      {:error, form} ->
        {:noreply, socket |> assign(form: form) |> push_event("focus-first-error", %{})}
    end
  end

  def handle_event("shuffle_snow", _params, socket) do
    form = AshPhoenix.Form.update_params(socket.assigns.form, &Map.put(&1, "voucher_snow_seed", to_string(snow_seed())))
    {:noreply, socket |> assign(form: form) |> render_preview()}
  end

  # A sale already placed by its webhook can't be released, and the page starts over regardless.
  def handle_event("start_over", _params, socket) do
    if sale = socket.assigns.sale do
      Orders.release_gift_voucher_sale(sale.id, socket.assigns.visitor_id, actor: socket.assigns.current_user)
    end

    {:noreply,
     socket
     |> push_event("scroll-top", %{})
     |> push_navigate(to: ~q"/#{language}/gift-voucher", replace: true)}
  end

  def handle_event("retry_preview", _params, socket), do: {:noreply, render_preview(socket)}

  def handle_event("change", _params, socket) do
    {:noreply, push_patch(socket, to: ~q"/#{language}/gift-voucher")}
  end

  # A retry after a declined card, or after changing the voucher, reuses the
  # PaymentIntent made here at the current amount.
  def handle_event("pay", _params, socket) do
    case Orders.prepare_checkout_payment(socket.assigns.sale.id, actor: nil) do
      {:ok, %{payable: %{payment_intent_id: payment_intent_id}, client_secret: client_secret}} ->
        {:noreply,
         socket
         |> update(:sale, &%{&1 | payment_intent_id: payment_intent_id})
         |> push_event("stripe:process_payment", %{client_secret: client_secret})}

      {:error, error} ->
        Logger.error("Could not set up payment for gift voucher sale #{socket.assigns.sale.id}: #{inspect(error)}")

        {:noreply,
         socket
         |> put_flash(:error, ~t"Payment is temporarily unavailable. Please try again in a moment.")
         |> push_event("stripe:ready", %{})}
    end
  end

  def handle_event("stripe:error", %{"message" => message, "details" => details}, socket) do
    Logger.error("Stripe client error for gift voucher sale #{socket.assigns.sale.id}: #{message}: #{inspect(details)}")

    {:noreply,
     put_flash(socket, :error, ~t"Payment is temporarily unavailable. Please refresh the page and try again.")}
  end

  @impl true
  def handle_async(:preview, {:ok, {:ok, png}}, socket),
    do: {:noreply, assign(socket, preview: Base.encode64(png), preview_loading?: false)}

  # Keep the inputs retryable and hide the old image, which no longer represents them.
  def handle_async(:preview, result, socket) do
    Logger.warning("Gift voucher preview failed: #{inspect(result)}")
    {:noreply, assign(socket, preview_loading?: false, preview_error?: true, previewed: nil)}
  end

  # Rendered in a task, as Typst takes a moment. Only the latest render is shown,
  # and a change that doesn't touch the voucher, like the buyer's email, skips it.
  defp render_preview(socket) do
    case preview_voucher(socket.assigns) do
      voucher when voucher == socket.assigns.previewed ->
        socket

      voucher ->
        socket
        |> assign(previewed: voucher, preview_loading?: true, preview_error?: false)
        |> start_async(:preview, fn -> GiftVoucherPdf.preview(voucher) end)
    end
  end

  defp preview_voucher(%{sale: sale, editing?: false}) when not is_nil(sale) do
    %{
      amount: sale.grand_total,
      locale: sale.voucher_locale,
      style: sale.voucher_style,
      snow_seed: sale.voucher_snow_seed,
      recipient_name: sale.recipient_name,
      message: sale.card_message || ""
    }
  end

  defp preview_voucher(%{form: form, interacted?: interacted?}) do
    changeset = form.source.source
    message = Ash.Changeset.get_attribute(changeset, :card_message)

    %{
      amount: Ash.Changeset.get_argument(changeset, :amount) || @default_amount,
      locale: Ash.Changeset.get_attribute(changeset, :voucher_locale),
      style: Ash.Changeset.get_attribute(changeset, :voucher_style),
      snow_seed: Ash.Changeset.get_attribute(changeset, :voucher_snow_seed),
      recipient_name: Ash.Changeset.get_attribute(changeset, :recipient_name),
      message: if(interacted?, do: message || "", else: message)
    }
  end

  defp snow_seed, do: :rand.uniform(1_000_000)

  defp load_sale(sale), do: Ash.load!(sale, [:grand_total, :gift_voucher_line], authorize?: false)

  defp assign_form(%{assigns: %{editing?: true, sale: sale}} = socket) do
    form =
      sale
      |> AshPhoenix.Form.for_update(:revise_gift_voucher_sale,
        as: "form",
        actor: socket.assigns.current_user,
        params: %{"amount" => to_string(Decimal.to_integer(Decimal.round(sale.gift_voucher_line.unit_price)))}
      )
      |> to_form()

    assign(socket, form: form)
  end

  defp assign_form(socket) do
    user = socket.assigns.current_user
    locale = to_string(socket.assigns.locale)

    form =
      Order
      |> AshPhoenix.Form.for_create(:start_gift_voucher_sale,
        as: "form",
        actor: user,
        params: %{
          "amount" => to_string(@default_amount),
          "voucher_locale" => locale,
          "voucher_style" => "cream",
          "voucher_snow_seed" => to_string(@first_snow_seed),
          "customer_name" => user && user.name,
          "customer_email" => user && to_string(user.email)
        },
        transform_params: fn _form, params, _action ->
          Map.merge(params, %{"locale" => locale, "visitor_id" => socket.assigns.visitor_id})
        end
      )
      |> to_form()

    assign(socket, form: form)
  end
end

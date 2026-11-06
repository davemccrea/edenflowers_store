defmodule EdenflowersWeb.Store.GiftVoucherLive do
  @moduledoc """
  The Gift voucher checkout: what the voucher is for and who it's from, then
  card payment, on one page. It never touches the browser's cart, so flowers
  and a voucher are paid for separately.
  """

  use EdenflowersWeb, :live_view

  require Logger
  import EdenflowersWeb.StripeForm, only: [stripe_form: 1]

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Format
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.Payments.GiftVoucherPdf
  alias Edenflowers.Payments.GiftVoucherStyle

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @default_amount 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: ~t"Gift voucher",
       alternates: alternates("/#{language}/gift-voucher"),
       page_description:
         ~t"An Eden Flowers gift voucher, from 20 to 200 €, to spend on flowers, subscriptions and courses in Vaasa.",
       locale: Format.locale(),
       sale: nil,
       editing?: false,
       voucher_styles: online_voucher_styles(),
       preview: nil,
       previewed: nil
     )
     |> assign_form()
     |> render_preview()}
  end

  @impl true
  def render(assigns) do
    ~H"""
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
          <h1 class="page-title">{~t"Give a gift voucher"}</h1>
          <p class="mt-6 text-lg leading-relaxed">
            {~t"Give them flowers on their own terms: a bouquet when they need one, fresh flowers every few weeks with a subscription, or an evening on one of my courses. They can spend it here online or in my shop at Minimossen."}
          </p>
        </header>

        <div class="mt-10" data-testid="gift-voucher-checkout">
          <.form
            :if={is_nil(@sale) || @editing?}
            id="gift-voucher-form"
            for={@form}
            phx-change="validate"
            phx-submit="continue"
          >
            <%!-- The fields run down the left, and the preview sticks beside them while they're
                 filled in. On a phone the preview follows the style choice, before the words,
                 and sticks to the top of the screen above them, over the header, so the header
                 coming and going leaves it where it is. --%>
            <%!-- A field scrolled into view stops below the sticky preview, not under it. --%>
            <div class="grid gap-10 max-lg:[&_:is(input,textarea,select)]:scroll-mt-[calc((100vw-2rem)*148/210+5rem)] lg:grid-cols-2 lg:items-start lg:gap-x-16">
              <fieldset class="flex flex-col lg:col-start-1 lg:row-start-1">
                <legend class="eyebrow text-base-content/70 mb-5">{~t"Make it personal"}</legend>
                <%!-- Two styles to a row, everyday above Christmas. --%>
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

              <div class="bg-base-100 z-60 sticky top-0 -mx-4 min-w-0 px-4 py-3 after:bg-linear-to-b after:from-base-100 after:absolute after:inset-x-0 after:top-full after:h-8 after:to-transparent lg:top-[calc(var(--shy-header-offset,0px)+2rem)] lg:z-auto lg:col-start-2 lg:row-span-4 lg:row-start-1 lg:mx-0 lg:bg-transparent lg:px-0 lg:py-0 lg:after:hidden">
                <%!-- Tapping a Christmas voucher shuffles its snow. --%>
                <button
                  :if={GiftVoucherStyle.christmas?(@form[:voucher_style].value)}
                  type="button"
                  phx-click={JS.push("shuffle_snow", loading: "#gift-voucher-form")}
                  aria-label={~t"Shuffle the snow on the voucher"}
                  class="block w-full cursor-pointer"
                  data-testid="shuffle-snow"
                >
                  <.voucher_preview preview={@preview} loading?={@preview_loading?} />
                </button>
                <.voucher_preview
                  :if={!GiftVoucherStyle.christmas?(@form[:voucher_style].value)}
                  preview={@preview}
                  loading?={@preview_loading?}
                />
                <.input field={@form[:voucher_snow_seed]} type="hidden" />
              </div>

              <div class="flex flex-col gap-6 lg:col-start-1 lg:row-start-2 lg:-mt-4">
                <.input
                  label={~t"Who is it for?"}
                  field={@form[:recipient_name]}
                  type="text"
                  validate_live?
                  phx-debounce="400"
                  required
                />
                <.input
                  label={~t"Your message"}
                  field={@form[:card_message]}
                  type="textarea"
                  maxlength={Order.Checkout.voucher_message_length()}
                  phx-debounce="400"
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
                  <div class="text-base-content/70 -mt-3 flex flex-col items-start gap-2 text-sm sm:col-span-2">
                    <p>
                      {~t"You'll receive an email with a PDF, to print or forward on. The voucher is valid for a year from the day you buy it."}
                    </p>
                    <.link navigate={~q"/#{language}/terms" <> "#gift-vouchers"} class="link-underline-hover">
                      {~t"Gift voucher terms"}
                    </.link>
                  </div>
                </div>
              </fieldset>
            </div>
          </.form>

          <%!-- The preview comes first, so it's above the payment on a phone; on a wide
               screen it moves to the right of it. --%>
          <div :if={@sale && !@editing?} class="grid gap-8 lg:grid-cols-2 lg:items-start lg:gap-x-16">
            <div class="min-w-0 lg:col-start-2 lg:row-start-1">
              <.voucher_preview preview={@preview} loading?={@preview_loading?} />
            </div>
            <section aria-labelledby="pay-heading" data-testid="payment-section">
              <%!-- The form, and the button that submitted it, are gone: focus lands here instead of on <body>. --%>
              <h2
                id="pay-heading"
                tabindex="-1"
                phx-mounted={JS.focus()}
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

  # Sized before the image arrives, so the fields beside it don't jump. Dims
  # gently while a new preview renders, so only changes to the voucher dim it.
  defp voucher_preview(assigns) do
    ~H"""
    <div
      id="voucher-preview"
      class={["bg-base-100 aspect-[210/148] shadow-md lg:shadow-xl", if(@loading?,
    do: "opacity-70 transition-opacity duration-150 ease-out",
    else: "transition-opacity duration-500 ease-out")]}
      aria-busy={to_string(@loading?)}
    >
      <img
        :if={@preview}
        src={"data:image/png;base64," <> @preview}
        alt={~t"Preview of your gift voucher"}
        class="block h-full w-full"
        data-testid="voucher-preview"
      />
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, socket |> assign(form: AshPhoenix.Form.validate(socket.assigns.form, params)) |> render_preview()}
  end

  def handle_event("continue", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, sale} ->
        {:noreply,
         socket
         |> assign(sale: load_sale(sale), editing?: false)
         |> render_preview()
         |> EdenflowersWeb.Analytics.track("Gift voucher checkout started", %{}, once: "gift-voucher:#{sale.id}")}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  def handle_event("shuffle_snow", _params, socket) do
    form = AshPhoenix.Form.update_params(socket.assigns.form, &Map.put(&1, "voucher_snow_seed", to_string(snow_seed())))
    {:noreply, socket |> assign(form: form) |> render_preview()}
  end

  def handle_event("change", _params, socket) do
    {:noreply, socket |> assign(editing?: true) |> assign_form()}
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

  # A preview that fails to render keeps the last one; the voucher itself is unaffected.
  def handle_async(:preview, result, socket) do
    Logger.warning("Gift voucher preview failed: #{inspect(result)}")
    {:noreply, assign(socket, preview_loading?: false)}
  end

  # Rendered in a task, as Typst takes a moment. Only the latest render is shown,
  # and a change that doesn't touch the voucher, like the buyer's email, skips it.
  defp render_preview(socket) do
    case preview_voucher(socket.assigns) do
      voucher when voucher == socket.assigns.previewed ->
        socket

      voucher ->
        socket
        |> assign(previewed: voucher, preview_loading?: true)
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
      message: sale.card_message
    }
  end

  defp preview_voucher(%{form: form}) do
    changeset = form.source.source

    %{
      amount: Ash.Changeset.get_argument(changeset, :amount) || @default_amount,
      locale: Ash.Changeset.get_attribute(changeset, :voucher_locale),
      style: Ash.Changeset.get_attribute(changeset, :voucher_style),
      snow_seed: Ash.Changeset.get_attribute(changeset, :voucher_snow_seed),
      recipient_name: Ash.Changeset.get_attribute(changeset, :recipient_name),
      message: Ash.Changeset.get_attribute(changeset, :card_message)
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
          "voucher_snow_seed" => to_string(snow_seed()),
          "customer_name" => user && user.name,
          "customer_email" => user && to_string(user.email)
        },
        transform_params: fn _form, params, _action -> Map.put(params, "locale", locale) end
      )
      |> to_form()

    assign(socket, form: form)
  end
end

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
       christmas_offered?: Edenflowers.Fulfillment.get_shop_calendar!(authorize?: false).christmas_vouchers_online,
       preview: nil
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
                 filled in. On a phone the preview sits between the choices and the words. --%>
            <div class="grid gap-10 lg:grid-cols-2 lg:items-start lg:gap-x-16">
              <fieldset class="flex flex-col lg:col-start-1 lg:row-start-1">
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
                  <div :if={@christmas_offered?} class="sm:col-span-2">
                    <.input
                      :let={option}
                      label={~t"Style"}
                      field={@form[:voucher_style]}
                      type="radio-card"
                      options={[%{value: "cream", label: ~t"Regular"}, %{value: "christmas", label: ~t"Christmas"}]}
                    >
                      {option.label}
                      <span :if={option.value == "christmas"} aria-hidden="true">☃️🎄</span>
                    </.input>
                  </div>
                  <.input :if={!@christmas_offered?} field={@form[:voucher_style]} type="hidden" />
                </div>
              </fieldset>

              <div class="min-w-0 lg:top-[calc(var(--shy-header-offset,0px)+2rem)] lg:sticky lg:col-start-2 lg:row-span-3 lg:row-start-1">
                <.voucher_preview preview={@preview} loading?={@preview_loading?} />
                <.input field={@form[:voucher_snow_seed]} type="hidden" />
                <button
                  :if={to_string(@form[:voucher_style].value) == "christmas"}
                  type="button"
                  phx-click={
                    JS.push("shuffle_snow", loading: "#gift-voucher-form")
                    |> JS.transition("motion-safe:animate-[snow-pulse_500ms_ease-in-out]",
                      to: "#shuffle-snowflake",
                      time: 500
                    )
                  }
                  class="mt-3 inline-flex items-center gap-2 py-2.5"
                  data-testid="shuffle-snow"
                >
                  <span id="shuffle-snowflake" class="inline-block" aria-hidden="true">❄️</span>
                  <span class="link-underline-hover">{~t"Let it snow"}</span>
                </button>
              </div>
              <fieldset class="flex flex-col gap-6 lg:col-start-1 lg:row-start-2">
                <legend class="eyebrow text-base-content/70 mb-5">{~t"Written on it"}</legend>
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
                  rows="5"
                />
              </fieldset>

              <fieldset class="flex flex-col lg:col-start-1 lg:row-start-3">
                <legend class="eyebrow text-base-content/70 mb-5">{~t"Your details"}</legend>
                <div class="grid gap-6 sm:grid-cols-2">
                  <.input
                    label={~t"Your name"}
                    field={@form[:customer_name]}
                    type="text"
                    autocomplete="name"
                    required
                  />
                  <.input
                    label={~t"Your email"}
                    field={@form[:customer_email]}
                    type="email"
                    autocomplete="email"
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

          <div :if={@sale && !@editing?} class={beside_preview_grid()}>
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

  # The preview comes first, so it's above the fields on a phone; on a wide
  # screen it moves to the right of them.
  defp beside_preview_grid,
    do: "grid gap-8 lg:grid-cols-2 lg:items-start lg:gap-x-16"

  attr :preview, :string, required: true
  attr :loading?, :boolean, required: true

  # Sized before the image arrives, so the fields beside it don't jump. Dims
  # gently while a change is sent and the new preview renders, then fades back in.
  defp voucher_preview(assigns) do
    ~H"""
    <div class="min-w-0">
      <div
        id="voucher-preview"
        class={["bg-base-100 aspect-[210/148] shadow-xl", "in-[.phx-change-loading]:opacity-70 in-[.phx-change-loading]:duration-150", "in-[.phx-click-loading]:opacity-70 in-[.phx-click-loading]:duration-150", if(@loading?,
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
    form = socket.assigns.form
    params = Map.put(form.source.params, "voucher_snow_seed", to_string(snow_seed()))
    {:noreply, socket |> assign(form: AshPhoenix.Form.validate(form, params)) |> render_preview()}
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

  # Rendered in a task, as Typst takes a moment. Only the latest render is shown.
  defp render_preview(socket) do
    voucher = preview_voucher(socket.assigns)

    socket
    |> assign(preview_loading?: true)
    |> start_async(:preview, fn -> GiftVoucherPdf.preview(voucher) end)
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
    %{
      amount: integer_or_nil(form[:amount].value) || @default_amount,
      locale: to_string(form[:voucher_locale].value),
      style: to_string(form[:voucher_style].value),
      snow_seed: integer_or_nil(form[:voucher_snow_seed].value),
      recipient_name: presence(form[:recipient_name].value),
      message: presence(form[:card_message].value)
    }
  end

  defp integer_or_nil(value) do
    case Integer.parse(to_string(value)) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp snow_seed, do: :rand.uniform(1_000_000)

  defp presence(value) do
    case value && String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

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

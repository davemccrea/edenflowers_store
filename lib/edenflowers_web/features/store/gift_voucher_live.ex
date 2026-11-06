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
       editing?: false
     )
     |> assign_form()}
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
        <div class="grid items-start gap-10 lg:grid-cols-[minmax(0,1fr)_34rem] lg:gap-16">
          <div class="min-w-0 max-w-prose">
            <h1 class="page-title">{~t"Gift voucher"}</h1>
            <p class="mt-6 text-lg leading-relaxed">
              {~t"Not sure which flowers they'd love? Let them choose. A gift voucher from me can be spent on a bouquet, a flower subscription or one of my courses, here online or in my shop at Minimossen."}
            </p>

            <dl class="border-base-content/12 grid-cols-[auto_minmax(0,1fr)] mt-8 grid items-baseline gap-x-6 gap-y-3 border-t pt-6">
              <dt class="eyebrow text-base-content/70">{~t"Amount"}</dt>
              <dd class="tabular-nums">{~t"From 20 to 200 €"}</dd>

              <dt class="eyebrow text-base-content/70">{~t"Valid"}</dt>
              <dd>{~t"One year from the day you buy it"}</dd>

              <dt class="eyebrow text-base-content/70">{~t"Delivery"}</dt>
              <dd>
                {~t"I email you the voucher as a PDF, in Swedish, Finnish or English, to print or forward. You can also collect a gift card at Minimossen, with the voucher written on it."}
              </dd>
            </dl>

            <p class="text-base-content/70 mt-6">
              <.link navigate={~q"/#{language}/terms" <> "#gift-vouchers"} class="link-underline-hover">
                {~t"Gift voucher terms"}
              </.link>
            </p>
          </div>

          <aside
            class="bg-cream text-cream-content -mx-4 min-w-0 px-4 py-8 sm:mx-0 sm:p-9 lg:top-[calc(var(--shy-header-offset,0px)+2rem)] lg:sticky"
            data-testid="gift-voucher-checkout"
          >
            <section :if={is_nil(@sale) || @editing?} aria-labelledby="voucher-details">
              <h2 id="voucher-details" class="section-title mb-6">{~t"Your gift voucher"}</h2>

              <.form
                id="gift-voucher-form"
                for={@form}
                phx-change="validate"
                phx-submit="continue"
                class="flex flex-col gap-6"
              >
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
                <.input
                  label={~t"Who is it for?"}
                  field={@form[:recipient_name]}
                  type="text"
                  required
                />
                <.input
                  label={~t"Your message"}
                  field={@form[:card_message]}
                  type="textarea"
                  maxlength={Order.Checkout.voucher_message_length()}
                  rows="3"
                />
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
                </div>
                <.input
                  label={~t"I'd also like to collect a gift card at Minimossen"}
                  field={@form[:collect_voucher_card]}
                  type="checkbox"
                />

                <.button type="submit" variant="primary" size="lg" class="mt-2" data-testid="continue-to-payment">
                  {~t"Continue to payment"}
                </.button>
              </.form>
            </section>

            <section :if={@sale && !@editing?} aria-labelledby="pay-heading" data-testid="payment-section">
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
          </aside>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("continue", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, sale} ->
        {:noreply,
         socket
         |> assign(sale: load_sale(sale), editing?: false)
         |> EdenflowersWeb.Analytics.track("Gift voucher checkout started", %{}, once: "gift-voucher:#{sale.id}")}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
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
          "customer_name" => user && user.name,
          "customer_email" => user && to_string(user.email)
        },
        transform_params: fn _form, params, _action -> Map.put(params, "locale", locale) end
      )
      |> to_form()

    assign(socket, form: form)
  end
end

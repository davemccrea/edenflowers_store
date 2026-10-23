defmodule EdenflowersWeb.Courses.CoursePayLive do
  @moduledoc """
  The page behind a course booking's payment link, for what it still owes.
  The token in the URL is the only thing that grants access, so the page
  shows only that booking's course, seats and money.

  It always speaks the booking's language rather than the browser's.
  """
  use EdenflowersWeb, :live_view

  import Edenflowers.Actors

  alias Edenflowers.Courses
  alias Edenflowers.Format
  alias Edenflowers.Translations
  alias EdenflowersWeb.PaymentLink

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(%{"token" => token} = params, _session, socket) do
    case load_registration(token) do
      {:ok, registration} ->
        Localize.Plug.put_locale_from_session(
          %{Localize.Plug.PutLocale.session_key() => registration.locale},
          gettext: EdenflowersWeb.Gettext
        )

        if connected?(socket) do
          Phoenix.PubSub.subscribe(Edenflowers.PubSub, "course_registration:paid:#{registration.id}")
        end

        {:ok,
         socket
         |> assign(:page_title, ~t"Pay for your booking")
         |> assign(:locale, Format.locale())
         |> PaymentLink.mount(registration, params, fn -> load_registration(token) end)}

      _ ->
        {:ok, PaymentLink.broken_link(socket)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <div class="max-w-xl">
          <.flower name="flower-30" class="text-primary/70 mb-8 h-16 w-16" />

          <%= cond do %>
            <% @payable.status == :cancelled -> %>
              <h1 class="page-title mb-6">{~t"Booking cancelled"}</h1>
              <p class="leading-relaxed" data-testid="pay-cancelled">
                {~t"This booking has been cancelled, so there is nothing to pay. If you have any questions, just get in touch."}
              </p>
            <% not @payable.payment_link_open? -> %>
              <h1 class="page-title mb-6">{~t"Thank you"}</h1>
              <p class="leading-relaxed" data-testid="pay-paid">
                {~t"This booking is paid."}
              </p>
            <% @returned_from_stripe? -> %>
              <h1 class="page-title mb-6">{~t"Thank you"}</h1>
              <p role="status" class="leading-relaxed" data-testid="pay-confirming">
                {~t"Confirming your payment… You'll get a receipt by email once it's done."}
              </p>
            <% true -> %>
              <h1 class="page-title mb-6">{~t"Pay for your booking"}</h1>
          <% end %>

          <dl class="border-base-content/12 grid-cols-[auto_1fr] mt-10 grid items-baseline gap-x-6 gap-y-3 border-y py-6">
            <dt class="eyebrow text-base-content/70">{~t"Course"}</dt>
            <dd>{@payable.course.name}</dd>

            <dt class="eyebrow text-base-content/70">{~t"When"}</dt>
            <dd class="tabular-nums">
              {Format.weekday_date(@payable.course.date, @locale)}, {Format.time(
                @payable.course.start_time,
                @locale
              )}–{Format.time(@payable.course.end_time, @locale)}
            </dd>

            <dt class="eyebrow text-base-content/70">{~t"Places"}</dt>
            <dd class="tabular-nums">{@payable.seats_held}</dd>

            <dt class="eyebrow text-base-content/70">{~t"Total"}</dt>
            <dd class="tabular-nums" data-testid="pay-total">{Format.currency(@payable.total_due, @locale)}</dd>

            <%= if Decimal.positive?(@payable.amount_paid) do %>
              <dt class="eyebrow text-base-content/70">{~t"Paid so far"}</dt>
              <dd class="tabular-nums">{Format.currency(@payable.amount_paid, @locale)}</dd>

              <%= if @payable.payment_link_open? do %>
                <dt class="eyebrow text-base-content/70">{~t"Left to pay"}</dt>
                <dd class="font-semibold tabular-nums" data-testid="pay-balance">
                  {Format.currency(@payable.balance, @locale)}
                </dd>
              <% end %>
            <% end %>
          </dl>

          <PaymentLink.payment_form
            payable={@payable}
            returned_from_stripe?={@returned_from_stripe?}
            locale={@locale}
            billing_name={@payable.name}
            billing_email={@payable.email}
          />
        </div>
      </.container>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("pay", _params, socket) do
    {:noreply, PaymentLink.pay(socket, ~t"The booking changed. Please try again.")}
  end

  def handle_event("stripe:error", params, socket), do: {:noreply, PaymentLink.stripe_error(socket, params)}

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "course_registration:paid:" <> _}, socket),
    do: {:noreply, PaymentLink.paid(socket)}

  defp load_registration(token) do
    with {:ok, registration} <- Courses.get_registration_by_payment_link_token(token, actor: system_actor()) do
      {:ok, Map.update!(registration, :course, &Translations.translate/1)}
    end
  end
end

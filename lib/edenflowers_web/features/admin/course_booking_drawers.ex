defmodule EdenflowersWeb.Admin.CourseBookingDrawers do
  @moduledoc """
  The course page's drawers for adding a booking and for settling one's balance.
  """
  use EdenflowersWeb, :html

  import EdenflowersWeb.Admin.Components
  import EdenflowersWeb.Admin.Drawers

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Format

  attr :form, :any, required: true
  attr :course, :map, required: true
  attr :locale, :string, required: true
  attr :preview, Swoosh.Email, default: nil

  def booking_drawer(assigns) do
    ~H"""
    <.admin_drawer id="booking-drawer" title={~t"Add booking"} on_close={JS.push("close_booking")}>
      <.form
        :if={@form}
        for={@form}
        id={"booking-form-#{@course.id}"}
        phx-change="validate_booking"
        phx-submit="save_booking"
        class="flex min-h-0 flex-1 flex-col"
      >
        <.drawer_body>
          <p class="text-base-content/75 text-sm">
            {@course.name} · {Format.date(@course.date, @locale)}, {Format.time(@course.start_time, @locale)}
          </p>
          <div class="space-y-4">
            <.input field={@form[:name]} type="text" label={~t"Name"} class="input w-full" />
            <.input field={@form[:email]} type="email" label={~t"Email"} class="input w-full" />
            <div class="grid grid-cols-2 gap-x-3 gap-y-4">
              <.input
                field={@form[:seats]}
                type="number"
                label={~t"Seats"}
                min="1"
                max={CourseRegistration.max_seats()}
                class="input w-full"
              />
              <.input
                field={@form[:locale]}
                type="select"
                label={~t"Language"}
                options={[{"Svenska", "sv-FI"}, {"Suomi", "fi"}, {"English", "en-GB"}]}
                class="select w-full"
              />
            </div>
            <.customer_email
              id="booking-email"
              send={@form[:email_customer?]}
              label={~t"Email the payment link to the customer"}
              message={@form[:message]}
              preview={@preview}
              in_swedish={@form[:locale].value != "sv-FI" && @form[:in_swedish]}
            />
          </div>
        </.drawer_body>
        <.drawer_footer>
          <.button type="submit" variant="primary">{~t"Add booking"}</.button>
          <.button
            type="button"
            phx-click={JS.exec("phx-hide", to: "#booking-drawer") |> JS.push("close_booking")}
            variant="ghost"
          >
            {~t"Cancel"}
          </.button>
        </.drawer_footer>
      </.form>
    </.admin_drawer>
    """
  end

  attr :course, :map, required: true
  attr :registration, :any, required: true, doc: "the booking being settled, or nil"
  attr :mode, :atom, required: true, values: [:settle, :refund]
  attr :refund_params, :map, required: true
  attr :error, :string, default: nil
  attr :locale, :string, required: true
  attr :preview, Swoosh.Email, default: nil

  def settlement_drawer(assigns) do
    ~H"""
    <.admin_drawer id="settlement-drawer" title={settlement_title(@mode)}>
      <.drawer_body :if={@registration}>
        <.settlement_details course={@course} registration={@registration} locale={@locale} />
        <p :if={@error} role="alert" class="text-error text-sm">{@error}</p>
        <.refund_form
          :if={@mode == :refund and @registration.refundable?}
          id={"refund-#{@registration.id}"}
          record={@registration}
          email={@registration.email}
          locale={@locale}
          params={Map.get(@refund_params, @registration.id, %{})}
          preview={@preview}
          swedish_toggle?={@registration.locale != "sv-FI"}
        />
        <.collect_payment
          :if={@mode == :settle and @registration.to_collect?}
          course={@course}
          registration={@registration}
          locale={@locale}
        />
        <p :if={nothing_to_settle?(@registration, @mode)} class="text-base-content/75 text-sm">
          {~t"Nothing left to settle on this booking."}
        </p>
      </.drawer_body>
    </.admin_drawer>
    """
  end

  defp settlement_title(:refund), do: ~t"Refund"
  defp settlement_title(:settle), do: ~t"Collect payment"

  defp nothing_to_settle?(registration, :refund), do: not registration.refundable?
  defp nothing_to_settle?(registration, :settle), do: not registration.to_collect?

  attr :course, :map, required: true
  attr :registration, :map, required: true
  attr :locale, :string, required: true

  defp settlement_details(assigns) do
    ~H"""
    <div class="space-y-1">
      <p class="text-base-content font-medium">
        {@registration.name}
        <span :if={@registration.seats_held > 1} class="text-base-content/75 tabular-nums">
          +{@registration.seats_held - 1}
        </span>
        <.badge :if={@registration.status == :cancelled} tone={:tag} class="ml-1 align-middle">
          {~t"Cancelled"}
        </.badge>
      </p>
      <p class="text-base-content/75 break-all text-sm">{@registration.email}</p>
      <p class="text-base-content/75 text-sm">
        {@course.name} · {Format.date(@course.date, @locale)}, {Format.time(@course.start_time, @locale)}
      </p>
    </div>
    <dl class="divide-base-content/12 border-base-content/12 divide-y border-y text-sm tabular-nums">
      <div class="flex justify-between gap-4 py-2">
        <dt class="text-base-content/75">{~t"Paid"}</dt>
        <dd>{Format.currency(@registration.amount_paid, @locale)}</dd>
      </div>
      <div :if={@registration.to_collect?} class="flex justify-between gap-4 py-2">
        <dt class="text-base-content/75">{~t"To collect"}</dt>
        <dd class="font-semibold">{Format.currency(@registration.balance, @locale)}</dd>
      </div>
      <div
        :if={@registration.status == :cancelled and Decimal.positive?(@registration.kept_amount)}
        class="flex justify-between gap-4 py-2"
      >
        <dt class="text-base-content/75">{~t"Kept"}</dt>
        <dd>{Format.currency(@registration.kept_amount, @locale)}</dd>
      </div>
      <div :if={@registration.to_refund?} class="flex justify-between gap-4 py-2">
        <dt class="text-base-content/75">{~t"To refund"}</dt>
        <dd class="font-semibold">{Format.currency(Decimal.abs(@registration.balance), @locale)}</dd>
      </div>
    </dl>
    <div :if={@registration.status == :cancelled} class="space-y-2 text-sm">
      <p :if={@registration.cancellation_reason} class="whitespace-pre-line">
        <span class="text-base-content/75">{~t"Message"}:</span> {@registration.cancellation_reason}
      </p>
      <p class="text-base-content/75 break-all">
        {if @registration.cancellation_emailed_to,
          do: ~t"Cancellation emailed to #{email = @registration.cancellation_emailed_to}.",
          else: ~t"The customer wasn't emailed."}
      </p>
    </div>
    """
  end

  attr :course, :map, required: true
  attr :registration, :map, required: true
  attr :locale, :string, required: true

  defp collect_payment(assigns) do
    assigns = assign(assigns, :emailed?, payment_link_emailed?(assigns.registration))

    ~H"""
    <section class="space-y-3">
      <h3 class="eyebrow text-base-content/75">{~t"Payment link"}</h3>
      <div :if={@registration.payment_link_open?} class="flex gap-2">
        <input
          id={"payment-link-url-#{@registration.id}"}
          type="text"
          readonly
          aria-label={~t"Payment link"}
          value={EdenflowersWeb.PaymentLink.url_for(@registration)}
          class="input input-sm font-mono min-w-0 flex-1 text-xs"
        />
        <.copy_button
          id={"copy-payment-link-#{@registration.id}"}
          target={"#payment-link-url-#{@registration.id}"}
          label={~t"Copy payment link"}
        />
      </div>
      <p :if={@emailed?} class="text-base-content/75 text-sm">
        {~t"Emailed #{time = Format.datetime(@registration.payment_link_emailed_at, @locale)}"}
      </p>
      <div class="flex flex-wrap gap-2">
        <.button
          type="button"
          phx-click="open_email"
          phx-value-kind={if @registration.payment_reminder?, do: "payment_reminder", else: "payment_link"}
          phx-value-id={@registration.id}
          variant="primary"
          size="sm"
        >
          <.icon name="hero-envelope" class="h-4 w-4" />
          {cond do
            @registration.payment_reminder? -> ~t"Send payment reminder"
            @emailed? -> ~t"Resend payment link"
            true -> ~t"Email payment link"
          end}
        </.button>
        <.button
          :if={not @registration.payment_link_open?}
          type="button"
          phx-click="open_payment_link"
          phx-value-id={@registration.id}
          variant="secondary"
          size="sm"
        >
          {~t"Get payment link"}
        </.button>
      </div>
    </section>
    """
  end

  defp payment_link_emailed?(registration),
    do: registration.payment_link_open? and not is_nil(registration.payment_link_emailed_at)
end

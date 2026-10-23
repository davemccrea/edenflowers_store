defmodule EdenflowersWeb.PaymentLink do
  @moduledoc """
  The page a customer opens to pay an order or course booking online, and its URL.

  `PayLive` and `CoursePayLive` keep their own loading, summary and copy, and
  hand the rest to the functions here. The record is the `@payable` assign,
  loaded with `payment_link_open?`, `balance` and `payment_intent_id`.
  """
  use EdenflowersWeb, :verified_routes
  use GettextSigils, backend: EdenflowersWeb.Gettext
  use Phoenix.Component

  require Logger

  import Edenflowers.Actors
  import EdenflowersWeb.CoreComponents, only: [input: 1, stripe_form: 1]
  import Phoenix.LiveView

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Format
  alias Edenflowers.Payments

  def url_for(payable), do: EdenflowersWeb.Endpoint.url() <> path_for(payable)

  def path_for(%CourseRegistration{payment_link_token: token}) when is_binary(token), do: ~p"/courses/pay/#{token}"
  def path_for(%{payment_link_token: token}) when is_binary(token), do: ~p"/pay/#{token}"

  @doc """
  Assigns `payable`. `reload` reads it again by its token, as the page's
  mount did.
  """
  def mount(socket, payable, params, reload) do
    socket
    |> assign(payable: payable, reload: reload, returned_from_stripe?: params["redirect_status"] == "succeeded")
    |> maybe_flash_failed_payment(params)
  end

  def broken_link(socket) do
    socket
    |> put_flash(:error, ~t"This payment link doesn't work. Please get in touch.")
    |> push_navigate(to: ~q"/#{language}")
  end

  @doc """
  The `pay` event. Pays only if the record still owes what the form shows,
  else reloads the page with `changed_message`. The PaymentIntent is made or
  brought up to date here, so a crawler or a link preview never creates one.
  """
  def pay(%{assigns: %{payable: shown, reload: reload}} = socket, changed_message) do
    with {:ok, payable} <- reload.(),
         true <- payable.payment_link_open?,
         true <- Decimal.equal?(payable.balance, shown.balance) do
      start_payment(socket, payable)
    else
      _ ->
        socket
        |> put_flash(:error, changed_message)
        |> push_navigate(to: path_for(shown))
    end
  end

  defp start_payment(socket, payable) do
    with :ok <- Payments.update_amount(payable),
         {:ok, _payable, client_secret} <- Payments.setup(payable, system_actor()) do
      socket
      |> assign(:payable, payable)
      |> push_event("stripe:process_payment", %{client_secret: client_secret})
    else
      {:error, reason} ->
        Logger.error("Could not set up payment for #{describe(payable)}: #{inspect(reason)}")

        socket
        |> put_flash(:error, ~t"Payment is temporarily unavailable. Please try again in a moment.")
        |> push_event("stripe:ready", %{})
    end
  end

  def stripe_error(socket, %{"message" => message, "details" => details}) do
    Logger.error("Stripe client error for #{describe(socket.assigns.payable)}: #{message}: #{inspect(details)}")
    put_flash(socket, :error, ~t"Payment is temporarily unavailable. Please refresh the page and try again.")
  end

  @doc "For the record's paid broadcast."
  def paid(%{assigns: %{reload: reload}} = socket) do
    {:ok, payable} = reload.()
    assign(socket, payable: payable)
  end

  attr :payable, :map, required: true
  attr :returned_from_stripe?, :boolean, required: true
  attr :locale, :string, required: true
  attr :billing_name, :string, required: true
  attr :billing_email, :string, required: true, doc: "nil asks the customer for one before they pay"
  attr :billing_phone, :string, default: nil

  def payment_form(assigns) do
    ~H"""
    <section :if={@payable.payment_link_open? and not @returned_from_stripe?} class="mt-10" aria-label={~t"Payment"}>
      <.stripe_form
        id="pay-form"
        phx-submit="pay"
        amount={StripeAPI.to_stripe_amount(@payable.balance)}
        return_path={path_for(@payable)}
        billing_name={@billing_name}
        billing_email={@billing_email}
        billing_phone={@billing_phone}
      >
        <:before_button>
          <.input
            :if={is_nil(@billing_email)}
            name="customer_email"
            value=""
            type="email"
            label={~t"Email for your receipt"}
            autocomplete="email"
            required
          />
        </:before_button>
        {~t"Pay"} {Format.currency(@payable.balance, @locale)}
      </.stripe_form>
    </section>
    """
  end

  # A redirect-based method (MobilePay) comes back with `redirect_status=failed`
  # when the customer cancels or is declined in the app.
  defp maybe_flash_failed_payment(socket, %{"redirect_status" => "failed"}) do
    put_flash(socket, :error, ~t"Your payment didn't go through. Please try again or choose another payment method.")
  end

  defp maybe_flash_failed_payment(socket, _params), do: socket

  defp describe(%resource{id: id}), do: "#{inspect(resource)} #{id}"
end

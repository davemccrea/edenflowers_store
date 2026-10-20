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
  import EdenflowersWeb.CoreComponents, only: [stripe_form: 1]
  import Phoenix.LiveView

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Format
  alias Edenflowers.Payments

  def url_for(payable), do: EdenflowersWeb.Endpoint.url() <> path_for(payable)

  def path_for(%CourseRegistration{payment_link_token: token}) when is_binary(token), do: ~p"/courses/pay/#{token}"
  def path_for(%{payment_link_token: token}) when is_binary(token), do: ~p"/pay/#{token}"

  @doc """
  Assigns `payable` and sets up its payment. `reload` reads it again by its
  token, as the page's mount did.
  """
  def mount(socket, payable, params, reload) do
    socket
    |> assign(payable: payable, reload: reload, returned_from_stripe?: params["redirect_status"] == "succeeded")
    |> assign_payment()
    |> maybe_flash_failed_payment(params)
  end

  def broken_link(socket) do
    socket
    |> put_flash(:error, ~t"This payment link doesn't work. Please get in touch.")
    |> push_navigate(to: ~q"/#{language}")
  end

  @doc """
  The `pay` event. Pays only if the record still owes what the form shows,
  else reloads the page with `changed_message`.
  """
  def pay(%{assigns: %{payable: shown, reload: reload}} = socket, changed_message) do
    with {:ok, payable} <- reload.(),
         true <- payable.payment_link_open?,
         true <- payable.payment_intent_id == shown.payment_intent_id,
         :ok <- sync_amount(payable) do
      socket
      |> assign(:payable, payable)
      |> push_event("stripe:process_payment", %{})
    else
      _ ->
        socket
        |> put_flash(:error, changed_message)
        |> push_navigate(to: path_for(shown))
    end
  end

  def stripe_error(socket, %{"message" => message, "details" => details}) do
    Logger.error("Stripe client error for #{describe(socket.assigns.payable)}: #{message}: #{inspect(details)}")
    put_flash(socket, :error, ~t"Payment is temporarily unavailable. Please refresh the page and try again.")
  end

  @doc "For the record's paid broadcast."
  def paid(%{assigns: %{reload: reload}} = socket) do
    {:ok, payable} = reload.()
    assign(socket, payable: payable, client_secret: nil)
  end

  attr :payable, :map, required: true
  attr :client_secret, :string, required: true
  attr :payment_unavailable?, :boolean, required: true
  attr :returned_from_stripe?, :boolean, required: true
  attr :locale, :string, required: true
  attr :billing_name, :string, required: true
  attr :billing_email, :string, required: true
  attr :billing_phone, :string, default: nil

  def payment_form(assigns) do
    ~H"""
    <section :if={@payable.payment_link_open? and not @returned_from_stripe?} class="mt-10" aria-label={~t"Payment"}>
      <.stripe_form
        :if={@client_secret}
        id="pay-form"
        phx-submit="pay"
        client_secret={@client_secret}
        return_url={url_for(@payable)}
        billing_name={@billing_name}
        billing_email={@billing_email}
        billing_phone={@billing_phone}
      >
        {~t"Pay"} {Format.currency(@payable.balance, @locale)}
      </.stripe_form>

      <p :if={@payment_unavailable?} class="text-error" data-testid="stripe-unavailable">
        {~t"Payment is temporarily unavailable. Please try again in a moment."}
      </p>
    </section>
    """
  end

  # Stripe is only touched once the page is live, so a crawler or a link
  # preview never creates a PaymentIntent. Back from Stripe, the payment is
  # in flight and its PaymentIntent must not change.
  defp assign_payment(%{assigns: %{payable: payable}} = socket) do
    if connected?(socket) and payable.payment_link_open? and not socket.assigns.returned_from_stripe? do
      case client_secret(payable) do
        {:ok, client_secret} ->
          assign(socket, client_secret: client_secret, payment_unavailable?: false)

        {:error, reason} ->
          Logger.error("Could not set up payment for #{describe(payable)}: #{inspect(reason)}")
          assign(socket, client_secret: nil, payment_unavailable?: true)
      end
    else
      assign(socket, client_secret: nil, payment_unavailable?: false)
    end
  end

  # Jennie may have changed what's owed since the PaymentIntent was made, and
  # the link always charges the balance.
  defp client_secret(payable) do
    with :ok <- sync_amount(payable),
         {:ok, _payable, client_secret} <- Payments.setup(payable, system_actor()) do
      {:ok, client_secret}
    end
  end

  defp sync_amount(%{payment_intent_id: nil}), do: :ok

  defp sync_amount(payable) do
    case Payments.update_amount(payable) do
      {:ok, _payment_intent} -> :ok
      error -> error
    end
  end

  # A redirect-based method (MobilePay) comes back with `redirect_status=failed`
  # when the customer cancels or is declined in the app.
  defp maybe_flash_failed_payment(socket, %{"redirect_status" => "failed"}) do
    put_flash(socket, :error, ~t"Your payment didn't go through. Please try again or choose another payment method.")
  end

  defp maybe_flash_failed_payment(socket, _params), do: socket

  defp describe(%resource{id: id}), do: "#{inspect(resource)} #{id}"
end

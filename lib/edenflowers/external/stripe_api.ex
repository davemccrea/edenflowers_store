defmodule Edenflowers.External.StripeAPI.Behaviour do
  @moduledoc """
  Behaviour for Stripe API interactions.
  This allows us to mock Stripe API calls in tests.
  """

  @callback create_payment_intent(amount_cents :: integer(), metadata :: map()) :: {:ok, map()} | {:error, term()}
  @callback create_payment_intent_saving_card(amount_cents :: integer(), metadata :: map(), customer_id :: String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback create_customer(params :: map()) :: {:ok, map()} | {:error, term()}
  @callback charge_off_session(amount_cents :: integer(), params :: map(), idempotency_key :: String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback retrieve_payment_intent(order :: map()) :: {:ok, map()} | {:error, term()}
  @callback create_setup_intent(customer_id :: String.t(), metadata :: map()) :: {:ok, map()} | {:error, term()}
  @callback retrieve_setup_intent(setup_intent_id :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback retrieve_payment_method(payment_method_id :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback update_payment_intent(payment_intent_id :: String.t(), amount_cents :: integer()) ::
              {:ok, map()} | {:error, term()}
  @callback cancel_payment_intent(payment_intent :: map()) :: {:ok, map()} | {:error, term()}
  @callback list_refunds(payment_intent_id :: String.t()) :: {:ok, [map()]} | {:error, term()}
  @callback create_refund(payment_intent_id :: String.t(), amount_cents :: integer(), idempotency_key :: String.t()) ::
              {:ok, map()} | {:error, term()}
end

defmodule Edenflowers.External.StripeAPI do
  @moduledoc """
  Real implementation of Stripe API interactions.
  """

  @behaviour Edenflowers.External.StripeAPI.Behaviour

  @doc """
  Converts a decimal monetary value into the integer minor units (cents) Stripe
  expects.
  """
  def to_stripe_amount(value) do
    value
    |> Decimal.round(2)
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end

  @doc "Converts Stripe's integer minor units (cents) back into a decimal amount."
  def from_stripe_amount(cents) do
    cents
    |> Decimal.new()
    |> Decimal.div(100)
    |> Decimal.round(2)
  end

  @impl true
  def create_payment_intent(amount_cents, metadata) do
    Stripe.PaymentIntent.create(%{
      amount: amount_cents,
      currency: "EUR",
      automatic_payment_methods: %{enabled: true},
      metadata: metadata
    })
  end

  # Cards only: every later delivery is charged to this card off-session, and
  # the customer is told so.
  @impl true
  def create_payment_intent_saving_card(amount_cents, metadata, customer_id) do
    Stripe.PaymentIntent.create(%{
      amount: amount_cents,
      currency: "EUR",
      payment_method_types: ["card"],
      customer: customer_id,
      setup_future_usage: "off_session",
      metadata: metadata
    })
  end

  @impl true
  def create_customer(params) do
    Stripe.Customer.create(params)
  end

  # `params` names the saved card (`customer`, `payment_method`) and the
  # `metadata`. A card that is declined or needs the customer to authenticate
  # returns a `Stripe.Error` with `code: :card_error`.
  @impl true
  def charge_off_session(amount_cents, params, idempotency_key) do
    params
    |> Map.merge(%{amount: amount_cents, currency: "EUR", off_session: true, confirm: true})
    |> Stripe.PaymentIntent.create(headers: %{"Idempotency-Key" => idempotency_key})
  end

  @impl true
  def retrieve_payment_intent(%{payment_intent_id: payment_intent_id}) do
    Stripe.PaymentIntent.retrieve(payment_intent_id)
  end

  # Saves a replacement card to the Customer for charging off-session later.
  @impl true
  def create_setup_intent(customer_id, metadata) do
    Stripe.SetupIntent.create(%{
      customer: customer_id,
      usage: "off_session",
      payment_method_types: ["card"],
      metadata: metadata
    })
  end

  @impl true
  def retrieve_setup_intent(setup_intent_id) do
    Stripe.SetupIntent.retrieve(setup_intent_id)
  end

  @impl true
  def retrieve_payment_method(payment_method_id) do
    Stripe.PaymentMethod.retrieve(payment_method_id)
  end

  @impl true
  def update_payment_intent(payment_intent_id, amount_cents) do
    Stripe.PaymentIntent.update(payment_intent_id, %{amount: amount_cents})
  end

  @impl true
  def cancel_payment_intent(%{id: payment_intent_id}) do
    Stripe.PaymentIntent.cancel(payment_intent_id)
  end

  @impl true
  # stripity_stripe's generated Stripe.Refund.list/3 only covers the charge-scoped
  # /v1/charges/{charge}/refunds, so we call /v1/refunds ourselves.
  def list_refunds(payment_intent_id) do
    request =
      Stripe.Request.new_request()
      |> Stripe.Request.put_endpoint("/v1/refunds")
      |> Stripe.Request.put_params(%{payment_intent: payment_intent_id, limit: 100})
      |> Stripe.Request.put_method(:get)

    with {:ok, %Stripe.List{data: refunds}} <- Stripe.Request.make_request(request) do
      {:ok, refunds}
    end
  end

  @impl true
  def create_refund(payment_intent_id, amount_cents, idempotency_key) do
    Stripe.Refund.create(%{payment_intent: payment_intent_id, amount: amount_cents},
      headers: %{"Idempotency-Key" => idempotency_key}
    )
  end

  def dashboard_payment_url(nil), do: nil

  def dashboard_payment_url(payment_intent_id) do
    path =
      case Application.get_env(:edenflowers, :stripe_publishable_key) do
        "pk_live_" <> _ -> "/payments/#{payment_intent_id}"
        _ -> "/test/payments/#{payment_intent_id}"
      end

    "https://dashboard.stripe.com#{path}"
  end
end

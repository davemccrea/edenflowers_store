defmodule Edenflowers.External.StripeAPI.Behaviour do
  @moduledoc """
  Behaviour for Stripe API interactions.
  This allows us to mock Stripe API calls in tests.
  """

  @callback create_payment_intent(amount_cents :: integer(), metadata :: map()) :: {:ok, map()} | {:error, term()}
  @callback retrieve_payment_intent(order :: map()) :: {:ok, map()} | {:error, term()}
  @callback update_payment_intent(order :: map()) :: {:ok, map()} | {:error, term()}
  @callback cancel_payment_intent(payment_intent :: map()) :: {:ok, map()} | {:error, term()}
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

  @impl true
  def create_payment_intent(amount_cents, metadata) do
    Stripe.PaymentIntent.create(%{
      amount: amount_cents,
      currency: "EUR",
      automatic_payment_methods: %{enabled: true},
      metadata: metadata
    })
  end

  @impl true
  def retrieve_payment_intent(%{payment_intent_id: payment_intent_id}) do
    Stripe.PaymentIntent.retrieve(payment_intent_id)
  end

  @impl true
  def update_payment_intent(%{payment_intent_id: payment_intent_id, grand_total: grand_total}) do
    amount = to_stripe_amount(grand_total)

    Stripe.PaymentIntent.update(payment_intent_id, %{
      amount: amount
    })
  end

  @impl true
  def cancel_payment_intent(%{id: payment_intent_id}) do
    Stripe.PaymentIntent.cancel(payment_intent_id)
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

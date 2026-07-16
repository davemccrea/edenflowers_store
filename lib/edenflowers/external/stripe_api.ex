defmodule Edenflowers.External.StripeAPI.Behaviour do
  @moduledoc """
  Behaviour for Stripe API interactions.
  This allows us to mock Stripe API calls in tests.
  """

  @callback create_payment_intent(order :: map()) :: {:ok, map()} | {:error, term()}
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
  expects. The webhook handler reuses this so the amount it verifies is computed
  identically to the amount that was charged.
  """
  def to_stripe_amount(value) do
    value
    |> Decimal.round(2)
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end

  @impl true
  def create_payment_intent(%{grand_total: grand_total, id: id}) do
    amount = to_stripe_amount(grand_total)

    Stripe.PaymentIntent.create(%{
      amount: amount,
      currency: "EUR",
      automatic_payment_methods: %{enabled: true, allow_redirects: :never},
      metadata: %{
        "order_id" => id
      }
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
end

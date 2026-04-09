defmodule Edenflowers.StripeAPI.Behaviour do
  @moduledoc """
  Behaviour for Stripe API interactions.
  This allows us to mock Stripe API calls in tests.
  """

  @callback create_payment_intent(order :: map()) :: {:ok, map()} | {:error, term()}
  @callback retrieve_payment_intent(order :: map()) :: {:ok, map()} | {:error, term()}
  @callback update_payment_intent(order :: map()) :: {:ok, map()} | {:error, term()}
end

defmodule Edenflowers.StripeAPI do
  @moduledoc """
  Real implementation of Stripe API interactions.
  """

  @behaviour Edenflowers.StripeAPI.Behaviour

  @impl true
  def create_payment_intent(%{total: total, id: id}) do
    amount = convert_to_stripe_amount(total)

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
  def update_payment_intent(%{payment_intent_id: payment_intent_id, total: total}) do
    amount = convert_to_stripe_amount(total)

    Stripe.PaymentIntent.update(payment_intent_id, %{
      amount: amount
    })
  end

  defp convert_to_stripe_amount(value) do
    value
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end
end

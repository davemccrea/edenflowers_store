defmodule Edenflowers.StripeAPI do
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

  def retrieve_payment_intent(%{payment_intent_id: payment_intent_id}) do
    Stripe.PaymentIntent.retrieve(payment_intent_id)
  end

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

defmodule Edenflowers.Payments.Actions.PrepareLinkPayment do
  @moduledoc """
  Readies the PaymentIntent behind a payment link, for what the order or
  booking owes now. The token is the only access, and it never brings the
  visitor's saved cards: whoever opens a link may not be who it's for.
  Refuses a closed link or a changed Balance with `Payments.Errors.NotPayable`.
  """

  use Ash.Resource.Actions.Implementation

  import Edenflowers.Actors

  alias Edenflowers.Payments
  alias Edenflowers.Payments.Errors.NotPayable

  @impl true
  def run(input, _opts, _context) do
    with {:ok, payable} <-
           input.resource
           |> Ash.Query.for_read(:by_payment_link_token, %{token: input.arguments.token}, actor: system_actor())
           |> Ash.read_one(),
         :ok <- open(payable),
         :ok <- unchanged(payable, input.arguments.shown_balance),
         {:ok, payable, client_secret} <- Payments.prepare(payable, system_actor()) do
      {:ok, %{payable: payable, client_secret: client_secret}}
    end
  end

  defp open(%{payment_link_open?: true}), do: :ok
  defp open(_closed), do: {:error, NotPayable.exception(reason: :link_closed)}

  defp unchanged(payable, shown_balance) do
    if Decimal.equal?(payable.balance, shown_balance),
      do: :ok,
      else: {:error, NotPayable.exception(reason: :balance_changed)}
  end
end

defmodule Edenflowers.Payments.Workers.SendRefundedEmail do
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Orders.Order
  alias Edenflowers.Translations

  def new_for(record, %{amount: amount, payment_method: method} = arguments) do
    new(%{
      (Edenflowers.Payments.parent_key(record) |> to_string()) => record.id,
      "amount" => Decimal.to_string(amount),
      "payment_method" => to_string(method),
      "note" => arguments[:note]
    })
  end

  @impl true
  def perform(%Oban.Job{args: args}) do
    refund = %{
      amount: Decimal.new(args["amount"]),
      payment_method: String.to_existing_atom(args["payment_method"]),
      note: args["note"]
    }

    with {:ok, _result} <- args |> email(refund) |> Mailer.deliver() do
      Logger.info("Sent refunded email for #{inspect(Map.delete(args, "note"))}")
      :ok
    end
  end

  defp email(%{"order_id" => id}, refund) do
    order = Ash.get!(Order, id, load: [:customer_first_name, :payments], actor: system_actor())
    Email.order_refunded(order, refund)
  end

  defp email(%{"course_registration_id" => id}, refund) do
    registration = Ash.get!(CourseRegistration, id, load: [:course, :first_name, :payments], actor: system_actor())
    locale = String.to_existing_atom(registration.locale)
    Email.booking_refunded(Map.update!(registration, :course, &Translations.translate(&1, locale)), refund)
  end
end

defmodule Edenflowers.Payments.Workers.SendCancelledEmail do
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Orders.Order
  alias Edenflowers.Translations

  def new_for(record, %{refunded: refunded, to_return: to_return}, cancelled_by) do
    new(%{
      (Edenflowers.Payments.parent_key(record) |> to_string()) => record.id,
      "refunded_amount" => Decimal.to_string(refunded),
      "to_return" => Decimal.to_string(to_return),
      "cancelled_by" => to_string(cancelled_by)
    })
  end

  @impl true
  def perform(%Oban.Job{args: args}) do
    money = %{refunded: Decimal.new(args["refunded_amount"]), to_return: Decimal.new(args["to_return"])}

    with {:ok, _result} <- args |> email(money) |> Mailer.deliver() do
      Logger.info("Sent cancelled email for #{inspect(args)}")
      :ok
    end
  end

  defp email(%{"order_id" => id, "cancelled_by" => cancelled_by}, money) do
    order = Ash.get!(Order, id, load: [:customer_first_name, :payments], actor: system_actor())
    Email.order_cancelled(order, money, String.to_existing_atom(cancelled_by))
  end

  defp email(%{"course_registration_id" => id}, money) do
    registration = Ash.get!(CourseRegistration, id, load: [:course, :first_name, :payments], actor: system_actor())
    locale = String.to_existing_atom(registration.locale)
    Email.booking_cancelled(Map.update!(registration, :course, &Translations.translate(&1, locale)), money)
  end
end

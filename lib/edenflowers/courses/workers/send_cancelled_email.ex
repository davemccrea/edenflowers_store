defmodule Edenflowers.Courses.Workers.SendCancelledEmail do
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Translations

  def new_for(registration, %{refunded: refunded, to_return: to_return}) do
    new(%{
      "registration_id" => registration.id,
      "refunded_amount" => Decimal.to_string(refunded),
      "to_return" => Decimal.to_string(to_return)
    })
  end

  @impl true
  def perform(%Oban.Job{args: %{"registration_id" => id, "refunded_amount" => refunded, "to_return" => to_return}}) do
    registration = Ash.get!(CourseRegistration, id, load: [:course, :first_name, :payments], actor: system_actor())
    locale = String.to_existing_atom(registration.locale)
    registration = Map.update!(registration, :course, &Translations.translate(&1, locale))

    money = %{refunded: Decimal.new(refunded), to_return: Decimal.new(to_return)}

    with {:ok, _result} <- registration |> Email.booking_cancelled(money) |> Mailer.deliver() do
      Logger.info("Sent cancelled email for course registration #{id}")
      :ok
    end
  end
end

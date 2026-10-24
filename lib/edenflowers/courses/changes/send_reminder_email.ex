defmodule Edenflowers.Courses.Changes.SendReminderEmail do
  @moduledoc """
  Reminds a booking of its course the day before. One still owing gets the
  amount and its payment link too.
  """

  use Ash.Resource.Change

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Translations
  alias EdenflowersWeb.PaymentLink

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      registration = load_for_send(changeset.data)

      case registration |> Email.course_reminder(PaymentLink.url_if_open(registration)) |> Mailer.deliver() do
        {:ok, _result} ->
          Logger.info("Sent reminder email for course registration #{registration.id}")
          Ash.Changeset.force_change_attribute(changeset, :reminder_emailed_at, DateTime.utc_now())

        {:error, error} ->
          Ash.Changeset.add_error(changeset, "Failed to send reminder email: #{inspect(error)}")
      end
    end)
  end

  defp load_for_send(registration) do
    registration
    |> Ash.load!([:course, :first_name, :balance, :payment_link_open?], actor: system_actor())
    |> Translations.in_own_locale()
  end
end

defmodule Edenflowers.Courses.CourseRegistration.Changes.SendReminderEmail do
  @moduledoc "Reminds a booking of its course the day before."

  use Ash.Resource.Change

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Translations

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      registration = load_for_send(changeset.data)

      case registration |> Email.course_reminder() |> Mailer.deliver() do
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
    |> Ash.load!([:course, :first_name, :balance], actor: system_actor())
    |> Translations.in_own_locale()
  end
end

defmodule Edenflowers.Courses.CourseRegistration.Changes.SendReminderEmail do
  @moduledoc "Sends a course reminder explicitly requested by Jennie."

  use Ash.Resource.Change

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Email
  alias Edenflowers.Email.Edits
  alias Edenflowers.Mailer
  alias Edenflowers.Translations

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      registration = load_for_send(changeset.data)

      case registration
           |> Email.course_reminder()
           |> Edits.apply_to(Edits.from_changeset(changeset))
           |> Mailer.deliver() do
        {:ok, _result} ->
          Logger.info("Sent reminder email for course registration #{registration.id}")
          Ash.Changeset.force_change_attribute(changeset, :reminder_emailed_at, DateTime.utc_now())

        {:error, error} ->
          Ash.Changeset.add_error(changeset, "Failed to send reminder email: #{inspect(error)}")
      end
    end)
  end

  @doc "What `Email.course_reminder/1` reads."
  def load, do: [:course, :first_name, :balance]

  @doc "Loads what `Email.course_reminder/1` reads, with the course in the booking's language."
  def load_for_send(registration) do
    registration
    |> Ash.load!(load(), actor: system_actor())
    |> Translations.in_own_locale()
  end
end

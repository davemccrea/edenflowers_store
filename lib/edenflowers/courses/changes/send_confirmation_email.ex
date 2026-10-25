defmodule Edenflowers.Courses.Changes.SendConfirmationEmail do
  @moduledoc """
  Sends a paid course booking its confirmation, with the receipt attached.
  """

  use Ash.Resource.Change

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Orders.Receipt
  alias Edenflowers.Translations

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      registration = load_for_send(changeset.data)

      case deliver(registration, Ash.Changeset.get_argument(changeset, :message)) do
        :ok ->
          Logger.info("Sent confirmation email for course registration #{registration.id}")
          now = DateTime.utc_now()
          Ash.Changeset.force_change_attributes(changeset, confirmation_emailed_at: now, receipt_emailed_at: now)

        {:error, error} ->
          Ash.Changeset.add_error(changeset, "Failed to send confirmation email: #{inspect(error)}")
      end
    end)
  end

  defp deliver(registration, message) do
    with {:ok, pdf} <- Receipt.generate(registration),
         {:ok, _result} <-
           registration
           |> Email.course_confirmation(message)
           |> Swoosh.Email.attachment(Receipt.attachment(pdf, registration.reference))
           |> Mailer.deliver() do
      :ok
    end
  end

  defp load_for_send(registration) do
    registration
    |> Ash.load!([:course, :payments, :first_name, :amount_paid, :balance], actor: system_actor())
    |> translate_course()
  end

  # Course names are stored per locale; the email and receipt should read in
  # the language the customer booked in.
  defp translate_course(registration) do
    locale = String.to_existing_atom(registration.locale)
    Map.update!(registration, :course, &Translations.translate(&1, locale))
  end
end

defmodule Edenflowers.Courses.CourseRegistration.Changes.SendConfirmationEmail do
  @moduledoc """
   Confirms booked places, attaching a receipt only for actual recorded money.
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
          stamp_sent(changeset, registration)

        {:error, error} ->
          Ash.Changeset.add_error(changeset, "Failed to send confirmation email: #{inspect(error)}")
      end
    end)
  end

  defp stamp_sent(changeset, registration) do
    now = DateTime.utc_now()
    changeset = Ash.Changeset.force_change_attribute(changeset, :confirmation_emailed_at, now)

    changeset =
      if registration.payment_link_open? and registration.payment_terms != :invoice,
        do: Ash.Changeset.force_change_attribute(changeset, :payment_link_emailed_at, now),
        else: changeset

    if Decimal.positive?(registration.amount_paid),
      do: Ash.Changeset.force_change_attribute(changeset, :receipt_emailed_at, now),
      else: changeset
  end

  defp deliver(registration, message) do
    email = Email.course_confirmation(registration, message)

    if Decimal.positive?(registration.amount_paid),
      do: deliver_with_receipt(email, registration),
      else: deliver_email(email)
  end

  defp deliver_with_receipt(email, registration) do
    with {:ok, pdf} <- Receipt.generate(registration) do
      email
      |> Swoosh.Email.attachment(Receipt.attachment(pdf, registration.reference))
      |> deliver_email()
    end
  end

  defp deliver_email(email) do
    case Mailer.deliver(email) do
      {:ok, _result} -> :ok
      error -> error
    end
  end

  defp load_for_send(registration) do
    registration
    |> Ash.load!([:course, :payments, :first_name, :amount_paid, :balance, :payment_link_open?], actor: system_actor())
    |> translate_course()
  end

  # Course names are stored per locale; the email and receipt should read in
  # the language the customer booked in.
  defp translate_course(registration) do
    locale = String.to_existing_atom(registration.locale)
    Map.update!(registration, :course, &Translations.translate(&1, locale))
  end
end

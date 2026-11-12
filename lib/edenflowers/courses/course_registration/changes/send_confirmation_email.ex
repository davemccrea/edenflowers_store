defmodule Edenflowers.Courses.CourseRegistration.Changes.SendConfirmationEmail do
  @moduledoc """
   Confirms booked places, attaching a receipt only for actual recorded money.
  """

  use Ash.Resource.Change

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Email
  alias Edenflowers.Email.Edits
  alias Edenflowers.Mailer
  alias Edenflowers.Orders.Receipt
  alias Edenflowers.Translations

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      registration = load_for_send(changeset.data)
      edits = Edits.from_changeset(changeset)

      case deliver(registration, edits) do
        :ok ->
          Logger.info("Sent confirmation email for course registration #{registration.id}")

          changeset
          |> Ash.Changeset.set_context(%{paper_trail_metadata: Edits.for_log(edits)})
          |> stamp_sent(registration)

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

    if receipt?(registration),
      do: Ash.Changeset.force_change_attribute(changeset, :receipt_emailed_at, now),
      else: changeset
  end

  defp deliver(registration, edits) do
    # A booking Jennie enters opens its link as it is saved, after the preview she edited.
    url = if registration.payment_link_token, do: EdenflowersWeb.PaymentLink.url_for(registration)

    with {:ok, pdf} <- receipt_pdf(registration) do
      registration |> email(pdf) |> Edits.apply_to(edits, url) |> deliver_email()
    end
  end

  @doc """
  The confirmation for a booking loaded with `load/0`, its course in the
  booking's language, with the receipt `pdf` attached only when money was
  received.
  """
  def email(registration, pdf) do
    email = Email.course_confirmation(registration)

    if receipt?(registration),
      do: Swoosh.Email.attachment(email, Receipt.attachment(pdf, registration.reference)),
      else: email
  end

  defp receipt_pdf(registration),
    do: if(receipt?(registration), do: Receipt.generate(registration), else: {:ok, nil})

  defp receipt?(registration), do: Decimal.positive?(registration.amount_paid)

  defp deliver_email(email) do
    case Mailer.deliver(email) do
      {:ok, _result} -> :ok
      error -> error
    end
  end

  @doc "What the booking is loaded with to build its email and receipt."
  def load, do: [:first_name, :amount_paid, :balance, :payment_link_open?] ++ Receipt.registration_load()

  defp load_for_send(registration) do
    registration
    |> Ash.load!(load(), actor: system_actor())
    |> translate_course()
  end

  # Course names are stored per locale; the email and receipt should read in
  # the language the customer booked in.
  defp translate_course(registration) do
    locale = String.to_existing_atom(registration.locale)
    Map.update!(registration, :course, &Translations.translate(&1, locale))
  end
end

defmodule Edenflowers.Courses.Changes.SendConfirmationEmail do
  @moduledoc """
  Sends a course booking confirmation, including a receipt when payment has
  settled. A booking still awaiting payment gets its payment link instead,
  or a Payment reminder once the course is over.
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
        {:ok, changes} ->
          Logger.info("Sent confirmation email for course registration #{registration.id}")

          changes
          |> Map.put(:confirmation_emailed_at, DateTime.utc_now())
          |> then(&Ash.Changeset.force_change_attributes(changeset, &1))

        {:error, error} ->
          Ash.Changeset.add_error(changeset, "Failed to send confirmation email: #{inspect(error)}")
      end
    end)
  end

  defp deliver(registration, message) do
    if Decimal.positive?(registration.balance),
      do: deliver_without_receipt(registration, message),
      else: deliver_with_receipt(registration, message)
  end

  # Only a booking awaiting payment owes anything, and it always has a link.
  defp deliver_without_receipt(%{payment_link_open?: true} = registration, message) do
    url = EdenflowersWeb.PaymentLink.url_for(registration)

    email =
      if Date.before?(registration.course.date, Edenflowers.ShopTime.today()),
        do: Email.payment_reminder(registration, url, message),
        else: Email.course_payment_link(registration, url, message)

    with {:ok, _result} <- Mailer.deliver(email) do
      {:ok, %{payment_link_emailed_at: DateTime.utc_now()}}
    end
  end

  defp deliver_with_receipt(registration, message) do
    with {:ok, pdf} <- Receipt.generate(registration),
         {:ok, _result} <-
           registration
           |> Email.course_confirmation(message)
           |> Swoosh.Email.attachment(Receipt.attachment(pdf, registration.reference))
           |> Mailer.deliver() do
      {:ok, %{receipt_emailed_at: DateTime.utc_now()}}
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

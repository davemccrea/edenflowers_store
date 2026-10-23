defmodule Edenflowers.Courses.Changes.SendPaymentLinkEmail do
  @moduledoc """
  Emails a course customer the private link for paying a remaining balance:
  as the course payment link before the course (`email: :payment_link`), or
  as the Payment reminder Jennie sends by hand (`:payment_reminder`).
  """

  use Ash.Resource.Change

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Translations

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      registration = load_for_send(changeset.data)
      token = Ash.Changeset.get_attribute(changeset, :payment_link_token)
      url = EdenflowersWeb.PaymentLink.url_for(%{registration | payment_link_token: token})

      if Decimal.positive?(registration.balance),
        do: deliver(changeset, registration, url, Keyword.get(opts, :email, :payment_link)),
        else: Ash.Changeset.add_error(changeset, field: :balance, message: "nothing is owed")
    end)
  end

  defp deliver(changeset, registration, url, kind) do
    message = Ash.Changeset.get_argument(changeset, :message)

    case registration |> email(kind, url, message) |> Mailer.deliver() do
      {:ok, _result} ->
        Logger.info("Sent payment link email for course registration #{registration.id}")
        Ash.Changeset.force_change_attribute(changeset, :payment_link_emailed_at, DateTime.utc_now())

      {:error, error} ->
        Ash.Changeset.add_error(changeset, "Failed to send payment link email: #{inspect(error)}")
    end
  end

  defp email(registration, :payment_link, url, message), do: Email.course_payment_link(registration, url, message)
  defp email(registration, :payment_reminder, url, message), do: Email.payment_reminder(registration, url, message)

  # Read fresh: the courses page's copy can predate a payment, and the email says what's owed.
  defp load_for_send(registration) do
    CourseRegistration
    |> Ash.get!(registration.id, load: [:course, :first_name, :amount_paid, :balance], actor: system_actor())
    |> Map.update!(:course, &Translations.translate(&1, String.to_existing_atom(registration.locale)))
  end
end

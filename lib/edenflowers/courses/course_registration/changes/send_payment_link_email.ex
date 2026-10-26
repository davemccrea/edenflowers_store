defmodule Edenflowers.Courses.CourseRegistration.Changes.SendPaymentLinkEmail do
  @moduledoc """
  Emails a course customer the private link for paying a remaining balance:
   as a Payment reminder for an already confirmed booking.
  """

  use Ash.Resource.Change

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Translations

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      registration = load_for_send(changeset.data)
      token = Ash.Changeset.get_attribute(changeset, :payment_link_token)
      url = EdenflowersWeb.PaymentLink.url_for(%{registration | payment_link_token: token})

      if Decimal.positive?(registration.balance),
        do: deliver(changeset, registration, url),
        else: Ash.Changeset.add_error(changeset, field: :balance, message: "nothing is owed")
    end)
  end

  defp deliver(changeset, registration, url) do
    message = Ash.Changeset.get_argument(changeset, :message)

    case registration |> Email.payment_reminder(url, message) |> Mailer.deliver() do
      {:ok, _result} ->
        Logger.info("Sent payment link email for course registration #{registration.id}")
        Ash.Changeset.force_change_attribute(changeset, :payment_link_emailed_at, DateTime.utc_now())

      {:error, error} ->
        Ash.Changeset.add_error(changeset, "Failed to send payment link email: #{inspect(error)}")
    end
  end

  # Read fresh: the courses page's copy can predate a payment, and the email says what's owed.
  defp load_for_send(registration) do
    CourseRegistration
    |> Ash.get!(registration.id,
      load: [:course, :first_name, :amount_paid, :balance, :payment_reminder?],
      actor: system_actor()
    )
    |> Translations.in_own_locale()
  end
end

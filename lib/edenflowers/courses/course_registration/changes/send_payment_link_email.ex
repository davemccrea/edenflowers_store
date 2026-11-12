defmodule Edenflowers.Courses.CourseRegistration.Changes.SendPaymentLinkEmail do
  @moduledoc """
  Sends a Payment reminder for an already confirmed course booking, including
  the private link where the customer can pay the remaining balance.
  """

  use Ash.Resource.Change

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Email
  alias Edenflowers.Email.Edits
  alias Edenflowers.Mailer
  alias Edenflowers.Translations

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      registration = load_for_send(changeset.data)
      url = payment_link_url(registration, Ash.Changeset.get_attribute(changeset, :payment_link_token))

      if Decimal.positive?(registration.balance),
        do: deliver(changeset, registration, url),
        else: Ash.Changeset.add_error(changeset, field: :balance, message: "nothing is owed")
    end)
  end

  defp deliver(changeset, registration, url) do
    case registration
         |> email(url)
         |> Edits.apply_to(Edits.from_changeset(changeset), url)
         |> Mailer.deliver() do
      {:ok, _result} ->
        Logger.info("Sent payment link email for course registration #{registration.id}")
        Ash.Changeset.force_change_attribute(changeset, :payment_link_emailed_at, DateTime.utc_now())

      {:error, error} ->
        Ash.Changeset.add_error(changeset, "Failed to send payment link email: #{inspect(error)}")
    end
  end

  @doc "What the booking is loaded with to build its email."
  def load, do: [:course, :first_name, :amount_paid, :balance, :payment_reminder?]

  @doc """
  The Payment reminder for a booking loaded with `load/0`, its course in the
  booking's language, giving the payment link at `url`.
  """
  def email(registration, url), do: Email.payment_reminder(registration, url)

  @doc "The payment link the email gives: the one sending it opens, whose `token` isn't in the booking read before yet."
  def payment_link_url(registration, token),
    do: EdenflowersWeb.PaymentLink.url_for(%{registration | payment_link_token: token})

  # Read fresh: the courses page's copy can predate a payment, and the email says what's owed.
  defp load_for_send(registration) do
    CourseRegistration
    |> Ash.get!(registration.id, load: load(), actor: system_actor())
    |> Translations.in_own_locale()
  end
end

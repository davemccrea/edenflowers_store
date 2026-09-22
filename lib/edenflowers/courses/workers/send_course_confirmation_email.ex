defmodule Edenflowers.Courses.Workers.SendCourseConfirmationEmail do
  # Webhook deliveries are at-least-once. The unique key on
  # `course_registration_id` collapses repeated enqueues to a single job.
  use Oban.Worker, unique: [keys: [:course_registration_id], period: :infinity]

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Courses
  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Orders.Receipt
  alias Edenflowers.Translations

  def enqueue(%{"course_registration_id" => registration_id} = args) do
    args
    |> __MODULE__.new()
    |> Oban.insert()
    |> case do
      {:ok, job} -> {:ok, job}
      {:error, changeset} -> {:error, {:enqueue_failed, registration_id, changeset}}
    end
  end

  def perform(%Oban.Job{args: %{"course_registration_id" => registration_id}}) do
    registration =
      registration_id
      |> Courses.get_registration_by_id!(actor: system_actor(), load: [:course, :first_name])
      |> translate_course()

    # Skip if a prior Oban attempt already delivered + marked.
    if registration.receipt_emailed_at do
      Logger.info("Confirmation email for course registration #{registration_id} already sent")
      :ok
    else
      send_with_receipt(registration)
    end
  end

  defp send_with_receipt(registration) do
    with {:ok, pdf} <- Receipt.generate(registration),
         sha = sha256_hex(pdf),
         email = build_email(registration, pdf),
         {:ok, _result} <- Mailer.deliver(email),
         {:ok, _registration} <-
           Courses.mark_registration_receipt_emailed(registration, sha, actor: system_actor()) do
      Logger.info("Sent confirmation email for course registration #{registration.id}")
      :ok
    end
  end

  defp build_email(registration, pdf) do
    attachment =
      Swoosh.Attachment.new(
        {:data, pdf},
        filename: "eden-flowers-#{registration.reference}.pdf",
        content_type: "application/pdf"
      )

    registration
    |> Email.course_confirmation()
    |> Swoosh.Email.attachment(attachment)
  end

  # Course names are stored per locale; the email and receipt should read in
  # the language the customer booked in.
  defp translate_course(registration) do
    locale = String.to_existing_atom(registration.locale)
    Map.update!(registration, :course, &Translations.translate(&1, locale))
  end

  defp sha256_hex(bytes) do
    :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  end
end

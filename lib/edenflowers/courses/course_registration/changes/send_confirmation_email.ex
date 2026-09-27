defmodule Edenflowers.Courses.CourseRegistration.Changes.SendConfirmationEmail do
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

      case deliver(registration) do
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

  # Nothing has been paid yet, so there is no receipt to send.
  defp deliver(%{pays_at_course?: true} = registration) do
    with {:ok, _result} <- registration |> Email.course_confirmation() |> Mailer.deliver() do
      {:ok, %{}}
    end
  end

  defp deliver(registration) do
    with {:ok, pdf} <- Receipt.generate(registration),
         {:ok, _result} <- registration |> build_email(pdf) |> Mailer.deliver() do
      {:ok, %{receipt_emailed_at: DateTime.utc_now(), receipt_sha256: sha256_hex(pdf)}}
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

  defp load_for_send(registration) do
    registration
    |> Ash.load!([:course, :first_name, :pays_at_course?], actor: system_actor())
    |> translate_course()
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

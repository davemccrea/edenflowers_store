defmodule Edenflowers.Courses do
  @moduledoc """
  Entry point for florist courses and their bookings.

  `Course` defines the event, capacity, and price. A `CourseRegistration` books
  places when accepted manually or paid at website checkout, with money recorded separately.
  """

  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  require Ash.Query

  @doc """
  Queues reminders for the course's current confirmed bookings only, in one
  transaction. `edits` holds Jennie's rewrite of any booking's reminder, as
  `%{subject: ..., body: ...}` by booking id; the rest go as built.
  """
  def send_course_reminders(course_id, edits \\ %{}, actor) do
    case Edenflowers.Repo.transaction(fn -> queue_reminders(course_id, edits, actor) end) do
      {:ok, {count, notifications}} ->
        Ash.Notifier.notify(notifications)
        {:ok, count}

      {:error, error} ->
        {:error, error}
    end
  end

  defp queue_reminders(course_id, edits, actor) do
    registrations =
      Edenflowers.Courses.CourseRegistration
      |> Ash.Query.filter(course_id == ^course_id and status == :confirmed)
      |> Ash.read!(actor: actor)

    notifications =
      Enum.flat_map(registrations, fn registration ->
        case Ash.update(registration, Map.get(edits, registration.id, %{}),
               action: :email_course_reminder,
               actor: actor,
               return_notifications?: true
             ) do
          {:ok, _registration, notifications} -> notifications
          {:error, error} -> Edenflowers.Repo.rollback(error)
        end
      end)

    {length(registrations), notifications}
  end

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Courses.Course do
      define :get_course_by_id, action: :read, get_by: [:id]
      define :get_course_by_slug, action: :read, get_by: [:slug]
      define :current_course_slug, action: :current_slug, args: [:param]
      define :list_upcoming_courses, action: :upcoming
    end

    resource Edenflowers.Courses.FormerCourseSlug

    resource Edenflowers.Courses.CourseRegistration do
      define :list_my_registrations, action: :mine
      define :list_unsettled_registrations, action: :unsettled
      define :register_for_course, action: :register
      define :get_checkout_registration, action: :checkout, get_by: [:id, :course_id]
      define :revise_registration, action: :revise
      define :add_registration_gift_voucher, action: :add_gift_voucher_with_code, args: [:code]
      define :clear_registration_gift_voucher, action: :clear_gift_voucher
      define :confirm_registration_paid_by_voucher, action: :confirm_paid_by_voucher
      define :add_registration_manually, action: :add_manually
      define :get_registration_by_id, action: :read, get_by: [:id]
      define :add_registration_payment_intent_id, action: :add_payment_intent_id, args: [:payment_intent_id]

      define :prepare_registration_checkout_payment,
        action: :prepare_checkout_payment,
        args: [:registration_id, :course_id]

      define :prepare_registration_link_payment, action: :prepare_link_payment, args: [:token, :shown_balance]

      define :confirm_registration_payment, action: :confirm_payment, args: [:payment_intent_id]
      define :open_registration_payment_link, action: :open_payment_link
      define :email_registration_payment_link, action: :email_payment_link
      define :send_registration_payment_reminder, action: :send_payment_reminder
      define :email_registration_confirmation, action: :email_receipt
      define :get_registration_by_payment_link_token, action: :by_payment_link_token, args: [:token]
      define :undo_registration_payment, action: :undo_payment, args: [:payment_id]
      define :record_registration_payment, action: :record_payment, args: [:amount, :payment_method]
      define :remove_registration_seat, action: :remove_seat
      define :cancel_registration, action: :cancel
    end
  end
end

defmodule Edenflowers.Courses.CourseRegistration.Emails do
  @moduledoc """
  The emails a registration sends its customer: the booking's confirmation and
  receipt, the reminder before the course, and payment reminders and receipts.
  """

  use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshOban]

  import Edenflowers.Actors

  alias Edenflowers.Courses.CourseRegistration.Changes
  alias Edenflowers.Payments.Changes, as: PaymentChanges

  oban do
    triggers do
      trigger :send_confirmation_email do
        action :send_confirmation_email
        queue :default
        max_attempts 3
        lock_for_update? false
        scheduler_cron false
        worker_module_name Edenflowers.Courses.Workers.SendConfirmationEmail
        scheduler_module_name Edenflowers.Courses.Schedulers.SendConfirmationEmail
        default_actor system_actor()
      end

      trigger :send_payment_received_email do
        action :send_payment_received_email
        queue :default
        max_attempts 3
        lock_for_update? false
        scheduler_cron false
        worker_module_name Edenflowers.Courses.Workers.SendPaymentReceivedEmail
        scheduler_module_name Edenflowers.Courses.Schedulers.SendPaymentReceivedEmail
        default_actor system_actor()
      end

      # Once a day, the day before the course. The stamp makes it one each.
      trigger :send_reminder_email do
        action :send_reminder_email
        queue :default
        max_attempts 3
        lock_for_update? false
        scheduler_cron "0 7 * * *"
        worker_module_name Edenflowers.Courses.Workers.SendReminderEmail
        scheduler_module_name Edenflowers.Courses.Schedulers.SendReminderEmail
        default_actor system_actor()

        where expr(
                status == :confirmed and is_nil(reminder_emailed_at) and
                  course.date == date_add(helsinki_today(), 1, :day)
              )
      end
    end
  end

  actions do
    # What its cancelled and refunded emails need.
    read :for_customer_email do
      prepare build(load: [:course, :first_name, :payments])
    end

    # Sent by hand only, like the order's. Opens the link if need be.
    update :send_payment_reminder do
      argument :message, :string
      validate attribute_equals(:status, :confirmed), message: "is not confirmed"
      change PaymentChanges.OpenPaymentLink
      change {Changes.SendPaymentLinkEmail, email: :payment_reminder}
      transaction? false
      require_atomic? false
    end

    update :send_payment_received_email do
      accept []
      argument :amount, :decimal
      argument :message, :string
      transaction? false
      require_atomic? false
      change PaymentChanges.SendPaymentReceivedEmail
    end

    update :send_confirmation_email do
      accept []
      argument :message, :string
      transaction? false
      require_atomic? false
      change Changes.SendConfirmationEmail
    end

    update :send_reminder_email do
      accept []
      transaction? false
      require_atomic? false
      change Changes.SendReminderEmail
    end

    # The confirmation again, with its receipt.
    update :email_receipt do
      accept []
      argument :message, :string
      validate attribute_equals(:status, :confirmed), message: "is not confirmed"
      transaction? false
      require_atomic? false
      change Changes.SendConfirmationEmail
    end
  end
end

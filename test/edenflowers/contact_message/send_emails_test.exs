defmodule Edenflowers.ContactMessage.SendEmailsTest do
  use Edenflowers.DataCase, async: true
  import Swoosh.TestAssertions

  alias Edenflowers.ContactMessage.SendEmails

  test "the sender gets a copy greeting them by first name, bcc Jennie" do
    assert {:ok, _} =
             perform_job(SendEmails, %{
               "name" => "Karin Holm",
               "email" => "karin@example.com",
               "phone" => nil,
               "message" => "A white heart, please.",
               "locale" => "en-GB"
             })

    from_address = Application.fetch_env!(:edenflowers, :mailer_from_address)

    assert_email_sent(fn email ->
      refute email.text_body =~ "Phone"
      assert email.to == [{"Karin Holm", "karin@example.com"}]
      assert email.bcc == [from_address]
      assert email.text_body =~ "Hi Karin,"
      assert email.text_body =~ "A white heart, please."
    end)
  end
end

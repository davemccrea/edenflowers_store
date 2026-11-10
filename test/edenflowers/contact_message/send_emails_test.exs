defmodule Edenflowers.ContactMessage.SendEmailsTest do
  use Edenflowers.DataCase, async: true
  import Swoosh.TestAssertions

  alias Edenflowers.ContactMessage.SendEmails

  test "the message goes to Jennie only, replying to the sender" do
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
      assert email.to == [from_address]
      assert email.reply_to == {"Karin Holm", "karin@example.com"}
      assert email.bcc == []
      assert email.text_body =~ "A white heart, please."
    end)
  end

  test "the acknowledgement goes to the typed address and repeats nothing typed" do
    assert {:ok, _} =
             perform_job(SendEmails, %{
               "acknowledgement" => true,
               "email" => "karin@example.com",
               "locale" => "en-GB"
             })

    assert_email_sent(fn email ->
      assert email.to == [{"", "karin@example.com"}]
      assert email.subject == "Your message to Eden Flowers"
      assert email.text_body =~ "Thank you for your message"
    end)
  end
end

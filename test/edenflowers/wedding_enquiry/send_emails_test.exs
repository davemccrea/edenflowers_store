defmodule Edenflowers.WeddingEnquiry.SendEmailsTest do
  use Edenflowers.DataCase, async: true
  import Swoosh.TestAssertions

  alias Edenflowers.WeddingEnquiry.SendEmails

  test "the enquiry goes to Jennie only, replying to the couple" do
    assert {:ok, _} =
             perform_job(SendEmails, %{
               "name" => "Anna Svensson",
               "email" => "anna@example.com",
               "wedding_date" => "2027-06-12",
               "venue" => "Smedsby",
               "guests" => nil,
               "message" => nil,
               "selection" => ["1 × Bridal bouquet"],
               "estimate" => "€110–€190",
               "locale" => "en-GB"
             })

    from_address = Application.fetch_env!(:edenflowers, :mailer_from_address)

    assert_email_sent(fn email ->
      refute email.text_body =~ "Number of guests"
      assert email.to == [from_address]
      assert email.reply_to == {"Anna Svensson", "anna@example.com"}
      assert email.bcc == []
      assert email.text_body =~ "Saturday 12.6.2027"
      assert email.text_body =~ "- 1 × Bridal bouquet"
      assert email.text_body =~ "Rough estimate, not a quote: €110–€190"
    end)
  end

  test "the acknowledgement goes to the typed address and repeats nothing typed" do
    assert {:ok, _} =
             perform_job(SendEmails, %{
               "acknowledgement" => true,
               "email" => "anna@example.com",
               "locale" => "en-GB"
             })

    assert_email_sent(fn email ->
      assert email.to == [{"", "anna@example.com"}]
      assert email.subject == "Your wedding enquiry to Eden Flowers"
      assert email.text_body =~ "Thank you for your enquiry"
    end)
  end
end

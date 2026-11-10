defmodule EdenflowersWeb.Admin.PaymentActionsTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Swoosh.TestAssertions

  alias EdenflowersWeb.Admin.PaymentActions

  for parent <- [:order, :booking] do
    @parent parent

    test "#{@parent} payment changes keep the validated form, action and preview together" do
      admin = generate(admin_user())
      record = payable(@parent) |> Ash.load!(:balance, authorize?: false)
      form = PaymentActions.payment_form(record, admin)
      params = %{"payment_method" => "zervant", "amount" => "30,00"}

      state = PaymentActions.change_payment(form, params, ["payment", "payment_method"], admin)
      assert state[:payment_form][:email_receipt?].value in [true, "true"]
      assert state[:preview].text_body =~ "30,00"

      params = Map.merge(params, %{"payment_method" => "voucher", "code" => "INVALID"})
      state = PaymentActions.change_payment(state[:payment_form], params, ["payment", "payment_method"], admin)
      assert state[:payment_form].source.action == :pay_with_gift_voucher
      assert state[:preview].text_body =~ "30,00"

      params = %{
        "payment_method" => "cash",
        "amount" => "12,50",
        "email_receipt?" => "true",
        "edit_email" => "true",
        "subject" => "Thank you",
        "body" => "Your payment arrived."
      }

      state = PaymentActions.change_payment(state[:payment_form], params, ["payment", "payment_method"], admin)
      assert state[:payment_form].source.action == :record_payment
      assert state[:payment_form][:subject].value == "Thank you"
      assert state[:payment_form][:body].value == "Your payment arrived."
      assert state[:preview].text_body =~ "12,50"
      refute state[:preview].text_body =~ "30,00"
      assert_no_email_sent()
    end

    test "#{@parent} refund changes keep the preview amount and method with the form" do
      admin = generate(admin_user())
      record = payable(@parent)
      parent_key = Edenflowers.Payments.parent_key(record)
      generate(payment([{parent_key, record.id}, {:amount, Decimal.new(100)}, {:method, :cash}]))
      record = Ash.load!(record, [:balance, :default_refund_method], authorize?: false)
      form = PaymentActions.refund_form(record, admin)
      params = %{"amount" => "12,50", "payment_method" => "cash"}

      state = PaymentActions.change_refund(form, params, ["refund", "payment_method"])
      assert state[:refund_form][:email_customer?].value in [false, "false"]
      assert state[:preview].text_body =~ "12,50"
      assert state[:preview].text_body =~ "in cash"

      params = %{"amount" => "7,00", "payment_method" => "zervant"}
      state = PaymentActions.change_refund(state[:refund_form], params, ["refund", "payment_method"])
      assert state[:refund_form][:email_customer?].value in [true, "true"]
      assert state[:preview].text_body =~ "7,00"
      assert state[:preview].text_body =~ "to your bank account"
      refute state[:preview].text_body =~ "12,50"
      assert_no_email_sent()
    end
  end

  defp payable(:order), do: placed_order()
  defp payable(:booking), do: generate(course_registration(status: :confirmed))
end

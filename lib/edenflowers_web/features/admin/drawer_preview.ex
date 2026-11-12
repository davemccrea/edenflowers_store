defmodule EdenflowersWeb.Admin.DrawerPreview do
  @moduledoc """
  Builds customer email previews for the drawers shared by order and course pages.
  Each preview uses the current form values: the payment amount, the refund
  amount and method, or the cancellation charge Jennie keeps.
  """

  alias Edenflowers.Email.Preview

  @send_fields %{payment: :email_receipt?, refunded: :email_customer?, cancelled: :email_customer?}

  @doc """
  The `preview` assign after Jennie changed the drawer's form, for `assign/2`:
  rebuilt while the email is ticked, nil while it isn't, and left as it was
  while she edits the email's own subject or text, which the template's
  preview doesn't depend on. `target` is the event's `_target`, if it has one.
  """
  def changed(kind, record, %Phoenix.HTML.Form{} = form, target) do
    cond do
      List.last(target || []) in ["subject", "body"] -> []
      form[@send_fields[kind]].value in [true, "true"] -> [preview: build(kind, record, form)]
      true -> [preview: nil]
    end
  end

  # The entered amount distinguishes a new payment from a neutral receipt copy.
  def build(:payment, record, %Phoenix.HTML.Form{} = form),
    do: Preview.build(:receipt, record, %{amount: form[:amount].value})

  def build(:refunded, record, %Phoenix.HTML.Form{} = form) do
    method =
      case Ash.Type.cast_input(Edenflowers.Payments.PaymentMethod, form[:payment_method].value) do
        {:ok, method} -> method
        _ -> nil
      end

    Preview.build(:refunded, record, %{refund: form[:amount].value, payment_method: method})
  end

  def build(:cancelled, record, %Phoenix.HTML.Form{} = form),
    do: Preview.build(:cancelled, record, %{charge: form[:cancellation_charge].value})

  # Email-only drawers have no payment or cancellation values to include in the preview.
  def build(kind, record, _params), do: Preview.build(kind, record, %{})
end

defmodule EdenflowersWeb.Admin.DrawerPreview do
  @moduledoc """
  The customer email a drawer would send, from its form as Jennie has filled it
  in so far: for a payment or refund, the amount and how she hands it back,
  or for a cancel the charge she keeps. What the order and course pages'
  drawers share.
  """

  alias Edenflowers.Email.Preview
  alias Edenflowers.Payments.CreditNote
  alias Edenflowers.Payments.Invoice

  def build(:invoice, %Invoice{} = invoice, _form), do: Preview.build(:invoice, invoice, %{})
  def build(:credit_note, %CreditNote{} = credit_note, _form), do: Preview.build(:credit_note, credit_note, %{})

  # The entered amount distinguishes a new payment from a neutral receipt copy.
  def build(:payment, record, %Phoenix.HTML.Form{} = form),
    do: Preview.build(:receipt, record, %{amount: form[:amount].value})

  def build(:refunded, record, %Phoenix.HTML.Form{} = form) do
    method = form[:payment_method].value
    Preview.build(:refunded, record, %{refund: form[:amount].value, payment_method: if(is_atom(method), do: method)})
  end

  def build(:cancelled, record, %Phoenix.HTML.Form{} = form),
    do: Preview.build(:cancelled, record, %{charge: form[:cancellation_charge].value})

  # The email drawer's kinds have nothing to enter but the email itself.
  def build(kind, record, _params), do: Preview.build(kind, record, %{})
end

defmodule Edenflowers.Payments.Validations.Sendable do
  @moduledoc """
  Refuses to email an Invoice that isn't `sendable?`, read fresh. The same
  calculation tells the admin whether to offer Send.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.load!(changeset.data, [:sendable?, :status], authorize?: false, reuse_values?: false) do
      %{sendable?: true} -> :ok
      %{status: :draft} -> {:error, message: ~t"Issue this invoice before sending it."}
      %{status: :paid} -> {:error, message: ~t"This invoice is paid, so there is nothing to send."}
      %{status: :cancelled} -> {:error, message: ~t"This invoice is cancelled. Send its credit note instead."}
    end
  end
end

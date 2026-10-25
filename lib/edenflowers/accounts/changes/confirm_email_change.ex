defmodule Edenflowers.Accounts.Changes.ConfirmEmailChange do
  @moduledoc """
  Moves the pending address into `email` once the code sent to it is given
  back, then clears the pending change so the code can't be used again.
  Wrong guesses are capped by the action's rate limit.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Accounts.Changes.RequestEmailChange

  @impl true
  def change(changeset, _opts, _context) do
    # A before_action, so the rate limit has already counted this attempt.
    Ash.Changeset.before_action(changeset, &confirm/1)
  end

  defp confirm(changeset) do
    user = changeset.data
    code = Ash.Changeset.get_argument(changeset, :code)

    cond do
      is_nil(user.pending_email) or DateTime.before?(user.pending_email_expires_at, DateTime.utc_now()) ->
        Ash.Changeset.add_error(changeset,
          field: :pending_email,
          message: ~t"That code has expired. Please try again."
        )

      not Plug.Crypto.secure_compare(RequestEmailChange.hash_code(code), user.pending_email_code_hash) ->
        Ash.Changeset.add_error(changeset, field: :code, message: ~t"That code isn't right.")

      true ->
        Ash.Changeset.force_change_attributes(changeset, %{
          email: user.pending_email,
          pending_email: nil,
          pending_email_code_hash: nil,
          pending_email_expires_at: nil
        })
    end
  end
end

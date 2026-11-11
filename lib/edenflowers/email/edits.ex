defmodule Edenflowers.Email.Edits do
  @moduledoc """
  Jennie's rewrite of an email she sends: the subject and text she edited in
  the drawer's preview, which go in place of the template's. The actions
  that send her emails take them as their `subject` and `body` arguments.
  """

  @doc "Jennie's rewrite of an action's email, from its `subject` and `body` arguments."
  def from_changeset(changeset) do
    %{subject: Ash.Changeset.get_argument(changeset, :subject), body: Ash.Changeset.get_argument(changeset, :body)}
  end

  @doc """
  Applies non-nil subject and body edits to `email`. If `payment_link_url`
  is supplied, replaces the preview's placeholder payment URL in the edited
  body with that URL.
  """
  def apply_to(email, edits, payment_link_url \\ nil) do
    email
    |> put_subject(edits[:subject])
    |> put_body(edits[:body], payment_link_url)
  end

  defp put_subject(email, nil), do: email
  defp put_subject(email, subject), do: Swoosh.Email.subject(email, subject)

  defp put_body(email, nil, _payment_link_url), do: email

  defp put_body(email, body, payment_link_url),
    do: Swoosh.Email.text_body(email, with_payment_link(body, payment_link_url))

  @doc "The log's record of a rewritten email, for `paper_trail_metadata`."
  def for_log(edits), do: %{email_subject: edits[:subject], email_body: edits[:body]}

  @doc "Returns the placeholder token used in previews before sending creates the real payment link."
  def placeholder_token, do: "new-link"

  defp with_payment_link(body, nil), do: body

  defp with_payment_link(body, url),
    do: String.replace(body, ~r{\S*/pay/(orders|courses)/#{placeholder_token()}}u, url)
end

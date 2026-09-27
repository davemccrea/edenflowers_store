defmodule Edenflowers.Chat.Conversation.Changes.GenerateName do
  use Ash.Resource.Change
  require Ash.Query

  alias ReqLLM.Context

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      conversation = changeset.data

      messages =
        Edenflowers.Chat.Message
        |> Ash.Query.filter(conversation_id == ^conversation.id)
        |> Ash.Query.limit(10)
        |> Ash.Query.select([:text, :source])
        |> Ash.Query.sort(inserted_at: :asc)
        |> Ash.read!(scope: context)

      prompt_messages =
        [
          Context.system("""
          Provide a short name for the current conversation.
          2-8 words, preferring more succinct names.
          RESPOND WITH ONLY THE NEW CONVERSATION NAME.
          """)
        ] ++
          [
            # Sent as one user message: replaying the turns would end on the agent's reply,
            # which the model treats as a partial answer to continue and returns nothing.
            Context.user(Enum.map_join(messages, "\n\n", &"#{&1.source}: #{&1.text}"))
          ]

      ReqLLM.generate_text("anthropic:claude-haiku-4-5", prompt_messages)
      |> case do
        {:ok, response} ->
          Ash.Changeset.force_change_attribute(
            changeset,
            :title,
            ReqLLM.Response.text(response)
          )

        {:error, error} ->
          {:error, error}
      end
    end)
  end
end

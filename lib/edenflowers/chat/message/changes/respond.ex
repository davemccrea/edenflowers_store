defmodule Edenflowers.Chat.Message.Changes.Respond do
  use Ash.Resource.Change
  require Ash.Query

  alias ReqLLM.Context

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      message = changeset.data

      messages =
        Edenflowers.Chat.Message
        |> Ash.Query.filter(conversation_id == ^message.conversation_id)
        |> Ash.Query.filter(id != ^message.id)
        |> Ash.Query.select([:text, :source, :tool_calls, :tool_results])
        |> Ash.Query.sort(inserted_at: :asc)
        |> Ash.read!(scope: context)
        |> Enum.concat([%{source: :user, text: message.text}])

      prompt_messages =
        [
          Context.system("""
          You are the admin assistant for Eden Flowers, a flower shop in Vaasa, Finland.
          You are talking with shop staff. Today is #{today_in_helsinki()}, Europe/Helsinki time.

          Answer from tool results only. If the tools can't answer something, say so.
          Never guess order, customer, course or money details.
          Amounts are in euros.

          Before marking an order fulfilled or an expense reviewed, name the record
          and ask for confirmation, unless the user has already named that exact record.

          Reply in the language the user writes in. Keep answers short.
          """)
        ] ++ message_chain(messages)

      new_message_id = Ash.UUIDv7.generate()

      final_state =
        prompt_messages
        |> AshAi.ToolLoop.stream(
          otp_app: :edenflowers,
          tools: true,
          model: "anthropic:claude-sonnet-5",
          actor: context.actor,
          tenant: context.tenant,
          context: Map.new(Ash.Context.to_opts(context))
        )
        |> Enum.reduce(%{text: "", tool_calls: [], tool_results: [], stream_error: nil}, fn
          {:content, content}, acc ->
            if content not in [nil, ""] do
              Edenflowers.Chat.Message
              |> Ash.Changeset.for_create(
                :upsert_response,
                %{
                  id: new_message_id,
                  response_to_id: message.id,
                  conversation_id: message.conversation_id,
                  text: content
                },
                actor: %AshAi{}
              )
              |> Ash.create!()
            end

            %{acc | text: acc.text <> (content || "")}

          {:tool_call, tool_call}, acc ->
            %{acc | tool_calls: append_event(acc.tool_calls, tool_call)}

          {:tool_result, %{id: id, result: result}}, acc ->
            %{
              acc
              | tool_results: append_event(acc.tool_results, normalize_tool_result(id, result))
            }

          {:error, reason}, acc ->
            %{acc | stream_error: reason}

          {:done, _}, acc ->
            acc

          _, acc ->
            acc
        end)

      stream_error_text = stream_error_text(final_state.stream_error)

      final_text =
        cond do
          stream_error_text && String.trim(final_state.text || "") != "" ->
            final_state.text <> "\n\n" <> stream_error_text

          stream_error_text ->
            stream_error_text

          String.trim(final_state.text || "") == "" &&
              (final_state.tool_calls != [] || final_state.tool_results != []) ->
            "Completed tool call."

          true ->
            final_state.text
        end

      if final_state.stream_error ||
           final_state.tool_calls != [] ||
           final_state.tool_results != [] ||
           final_text != "" do
        Edenflowers.Chat.Message
        |> Ash.Changeset.for_create(
          :upsert_response,
          %{
            id: new_message_id,
            response_to_id: message.id,
            conversation_id: message.conversation_id,
            complete: true,
            tool_calls: final_state.tool_calls,
            tool_results: final_state.tool_results,
            text: final_text
          },
          actor: %AshAi{}
        )
        |> Ash.create!()
      end

      changeset
    end)
  end

  defp today_in_helsinki do
    "Europe/Helsinki"
    |> DateTime.now!()
    |> Calendar.strftime("%A %-d %B %Y")
  end

  defp message_chain(messages) do
    Enum.map(messages, fn
      %{source: :agent, text: text} ->
        # Historical tool call replay can break provider request validation for prior call IDs.
        # Keep replay text-only; current turn tool usage is handled by AshAi.ToolLoop.
        Context.assistant(text || "")

      %{source: :user, text: text} ->
        Context.user(text || "")
    end)
  end

  defp append_event(items, value) when is_list(items), do: items ++ [value]
  defp append_event(_items, value), do: [value]

  defp normalize_tool_result(tool_call_id, {:ok, content, _raw}) do
    %{
      tool_call_id: tool_call_id,
      content: content,
      is_error: false
    }
  end

  defp normalize_tool_result(tool_call_id, {:error, content}) do
    %{
      tool_call_id: tool_call_id,
      content: content,
      is_error: true
    }
  end

  defp stream_error_text(nil), do: nil

  defp stream_error_text(:max_iterations_reached) do
    "I hit a response limit while generating this reply. Please try again."
  end

  defp stream_error_text(_reason) do
    "I hit an error while generating this response. Please try again."
  end
end

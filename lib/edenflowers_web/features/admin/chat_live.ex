defmodule EdenflowersWeb.Admin.ChatLive do
  use EdenflowersWeb, :live_view

  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @chat_ui_tools AshAi.ChatUI.Tools

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user} fill_viewport>
      <div class="flex min-h-0 flex-1 flex-col lg:flex-row">
        <section class="flex min-h-0 min-w-0 flex-1 flex-col lg:order-last">
          <header class="border-base-content/12 min-h-14 flex items-center gap-3 border-b px-4 py-2 sm:px-6 lg:px-8">
            <.link
              :if={@conversation}
              navigate={~p"/admin/chat"}
              aria-label={~t"All conversations"}
              class="text-base-content/65 -ml-2 p-2 transition-colors hover:text-base-content lg:hidden"
            >
              <.icon name="hero-arrow-left" class="h-4 w-4" />
            </.link>
            <h1 class="text-base-content min-w-0 flex-1 truncate text-base font-semibold">
              {conversation_title(@conversation)}
            </h1>
            <.link
              :if={@conversation}
              navigate={~p"/admin/chat"}
              aria-label={~t"New conversation"}
              class="btn btn-sm btn-primary btn-outline shrink-0"
            >
              <.icon name="hero-plus" class="h-4 w-4" />
              <span class="hidden sm:inline">{~t"New conversation"}</span>
            </.link>
            <button
              :if={@conversation}
              type="button"
              phx-click="delete_conversation"
              data-confirm={~t"Delete this conversation? This can't be undone."}
              aria-label={~t"Delete"}
              class="btn btn-ghost btn-sm text-error shrink-0"
            >
              <.icon name="hero-trash" class="h-4 w-4" />
              <span class="hidden sm:inline">{~t"Delete"}</span>
            </button>
          </header>

          <div class="min-h-0 flex-1 overflow-y-auto">
            <div
              :if={@conversation}
              id="message-container"
              phx-update="stream"
              class="mx-auto flex min-h-full w-full max-w-3xl flex-col-reverse gap-7 px-4 py-8 sm:px-6"
            >
              <div :for={{id, message} <- @streams.messages} id={id}>
                <div :if={message.source == :user} class="flex justify-end">
                  <p
                    class="bg-base-200 text-base-content max-w-[85%] whitespace-pre-wrap px-4 py-2.5 text-sm leading-relaxed"
                    phx-no-format
                  >{message.text}</p>
                </div>

                <div :if={message.source == :agent}>
                  <p
                    :if={tool_calls(message) != []}
                    class="text-base-content/60 mb-2.5 flex items-center gap-1.5 text-xs"
                  >
                    <.icon name="hero-magnifying-glass" class="h-3.5 w-3.5 shrink-0" />
                    {~t"Checked"} {tool_summary(message)}
                  </p>
                  <p
                    :for={result <- tool_results(message)}
                    :if={result.is_error}
                    class="text-error mb-2.5 flex items-center gap-1.5 text-xs"
                  >
                    <.icon name="hero-exclamation-triangle" class="h-3.5 w-3.5 shrink-0" />
                    {~t"This lookup failed:"} {humanize_tool(result.name)}
                  </p>
                  <div :if={String.trim(message.text || "") != ""} class="chat-prose">
                    {to_markdown(message.text)}
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div class="border-base-content/12 border-t">
            <div class="mx-auto w-full max-w-3xl px-4 py-4 sm:px-6">
              <p :if={@agent_responding} class="text-base-content/65 mb-3 flex items-center gap-2 text-sm" role="status">
                <span class="loading loading-dots loading-xs" />
                {~t"Thinking…"}
              </p>
              <.form
                :let={form}
                id="message-form"
                for={@message_form}
                phx-change="validate_message"
                phx-submit="send_message"
                class="flex items-center gap-2"
              >
                <label for={form[:text].id} class="sr-only">{~t"Message"}</label>
                <input
                  id={form[:text].id}
                  name={form[:text].name}
                  value={form[:text].value}
                  type="text"
                  phx-mounted={JS.focus()}
                  placeholder={~t"Ask a question…"}
                  class="input min-w-0 flex-1"
                  autocomplete="off"
                />
                <button type="submit" class="btn btn-primary shrink-0" aria-label={~t"Send"}>
                  <.icon name="hero-paper-airplane" class="h-4 w-4" />
                  <span class="hidden sm:inline">{~t"Send"}</span>
                </button>
              </.form>
            </div>
          </div>
        </section>

        <aside class={["border-base-content/12 flex-col lg:flex lg:w-72 lg:shrink-0 lg:border-r", if(@conversation, do: "hidden", else: "flex max-h-72 border-t lg:max-h-none lg:border-t-0")]}>
          <h2 class="text-base-content/65 px-5 pt-4 pb-2 text-xs font-semibold lg:pt-5">
            {~t"Conversations"}
          </h2>
          <nav class="min-h-0 flex-1 overflow-y-auto px-3 pb-4">
            <ul id="conversations-list" phx-update="stream" class="flex flex-col gap-0.5">
              <li :for={{id, conversation} <- @streams.conversations} id={id}>
                <.link
                  navigate={~p"/admin/chat/#{conversation.id}"}
                  aria-current={current_conversation?(@conversation, conversation) && "page"}
                  class={["block truncate border-l-2 px-3 py-2 text-sm transition-colors", if(current_conversation?(@conversation, conversation),
    do: "border-primary text-base-content bg-base-300/50 font-medium",
    else: "text-base-content/65 border-transparent hover:bg-base-300/40 hover:text-base-content")]}
                >
                  {conversation_title(conversation)}
                </.link>
              </li>
            </ul>
          </nav>
        </aside>
      </div>
    </Layouts.admin>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_user
    EdenflowersWeb.Endpoint.subscribe("chat:conversations:#{actor.id}")

    socket =
      socket
      |> assign(:page_title, ~t"Assistant")
      |> stream(
        :conversations,
        Edenflowers.Chat.my_conversations!(actor: actor, query: [sort: [inserted_at: :desc]])
      )
      |> assign(:agent_responding, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"conversation_id" => conversation_id}, _, socket) do
    actor = socket.assigns.current_user
    conversation = Edenflowers.Chat.get_conversation!(conversation_id, actor: actor)
    messages = Edenflowers.Chat.message_history!(conversation.id, stream?: true, actor: actor)

    cond do
      socket.assigns[:conversation] && socket.assigns[:conversation].id == conversation.id ->
        :ok

      socket.assigns[:conversation] ->
        EdenflowersWeb.Endpoint.unsubscribe("chat:messages:#{socket.assigns.conversation.id}")
        EdenflowersWeb.Endpoint.subscribe("chat:messages:#{conversation.id}")

      true ->
        EdenflowersWeb.Endpoint.subscribe("chat:messages:#{conversation.id}")
    end

    socket
    |> assign(:conversation, conversation)
    |> assign(:agent_responding, agent_response_pending?(messages))
    |> stream(:messages, messages)
    |> assign_message_form()
    |> then(&{:noreply, &1})
  end

  def handle_params(_, _, socket) do
    if socket.assigns[:conversation] do
      EdenflowersWeb.Endpoint.unsubscribe("chat:messages:#{socket.assigns.conversation.id}")
    end

    socket
    |> assign(:conversation, nil)
    |> assign(:agent_responding, false)
    |> stream(:messages, [])
    |> assign_message_form()
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_event("validate_message", %{"form" => params}, socket) do
    {:noreply, assign(socket, :message_form, AshPhoenix.Form.validate(socket.assigns.message_form, params))}
  end

  def handle_event("send_message", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.message_form, params: params) do
      {:ok, message} ->
        if socket.assigns.conversation do
          socket
          |> assign(:agent_responding, true)
          |> assign_message_form()
          |> stream_insert(:messages, message, at: 0)
          |> then(&{:noreply, &1})
        else
          {:noreply, push_navigate(socket, to: ~p"/admin/chat/#{message.conversation_id}")}
        end

      {:error, form} ->
        {:noreply, assign(socket, :message_form, form)}
    end
  end

  def handle_event("delete_conversation", _params, socket) do
    conversation = socket.assigns.conversation
    Edenflowers.Chat.delete_conversation!(conversation, actor: socket.assigns.current_user)

    {:noreply,
     socket
     |> stream_delete(:conversations, conversation)
     |> put_flash(:info, ~t"Conversation deleted")
     |> push_patch(to: ~p"/admin/chat")}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "chat:messages:" <> conversation_id, payload: message}, socket) do
    if socket.assigns.conversation && socket.assigns.conversation.id == conversation_id do
      socket =
        socket
        |> stream_insert(:messages, message, at: 0)
        |> update_agent_responding(message)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info(%Phoenix.Socket.Broadcast{topic: "chat:conversations:" <> _, payload: conversation}, socket) do
    socket =
      if current_conversation?(socket.assigns.conversation, conversation) do
        assign(socket, :conversation, conversation)
      else
        socket
      end

    {:noreply, stream_insert(socket, :conversations, conversation, at: 0)}
  end

  defp conversation_title(nil), do: ~t"New conversation"
  defp conversation_title(%{title: nil}), do: ~t"Untitled conversation"
  defp conversation_title(%{title: title}), do: title

  defp current_conversation?(nil, _conversation), do: false
  defp current_conversation?(current, conversation), do: current.id == conversation.id

  defp assign_message_form(socket) do
    opts =
      if socket.assigns.conversation do
        [private_arguments: %{conversation_id: socket.assigns.conversation.id}]
      else
        []
      end

    form =
      [actor: socket.assigns.current_user]
      |> Keyword.merge(opts)
      |> Edenflowers.Chat.form_to_create_message()
      |> to_form()

    assign(socket, :message_form, form)
  end

  defp tool_summary(message) do
    message
    |> tool_calls()
    |> Enum.map(&humanize_tool(&1.name))
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  # Tool names are code identifiers like "list_open_orders"; staff read "open orders".
  defp humanize_tool(nil), do: ""

  defp humanize_tool(name) do
    name
    |> to_string()
    |> String.replace_prefix("list_", "")
    |> String.replace_prefix("get_", "")
    |> String.replace("_", " ")
  end

  defp tool_calls(message), do: safe_extract(message).tool_calls

  defp tool_results(message), do: safe_extract(message).tool_results

  defp safe_extract(message) do
    case @chat_ui_tools.extract(message) do
      {:ok, extracted} -> extracted
      {:error, _} -> %{tool_calls: [], tool_results: []}
    end
  end

  defp message_source(%{source: source}), do: source
  defp message_source(%{"source" => source}), do: source
  defp message_source(_), do: nil

  defp message_complete?(%{complete: complete}), do: complete in [true, "true"]
  defp message_complete?(%{"complete" => complete}), do: complete in [true, "true"]
  defp message_complete?(_), do: false

  defp user_message?(message), do: message_source(message) in [:user, "user"]
  defp agent_message?(message), do: message_source(message) in [:agent, "agent"]

  defp update_agent_responding(socket, message) do
    cond do
      user_message?(message) -> assign(socket, :agent_responding, true)
      agent_message?(message) -> assign(socket, :agent_responding, !message_complete?(message))
      true -> socket
    end
  end

  defp agent_response_pending?(messages) do
    case Enum.find(messages, fn message -> user_message?(message) or agent_message?(message) end) do
      nil -> false
      message -> user_message?(message) || !message_complete?(message)
    end
  end

  defp to_markdown(text) do
    # MDEx needs unsafe: true to emit raw HTML so that sanitize can then clean it.
    # https://hexdocs.pm/mdex/MDEx.html#module-sanitize
    MDEx.to_html(text,
      extension: [strikethrough: true, tagfilter: true, table: true, autolink: true, tasklist: true],
      parse: [smart: true, relaxed_tasklist_matching: true, relaxed_autolinks: true],
      render: [unsafe: true],
      sanitize: MDEx.Document.default_sanitize_options()
    )
    |> case do
      {:ok, html} -> Phoenix.HTML.raw(html)
      {:error, _} -> text
    end
  end
end

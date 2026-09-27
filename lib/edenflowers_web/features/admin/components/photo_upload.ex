defmodule EdenflowersWeb.Admin.PhotoUpload do
  @moduledoc """
  Photo uploads for `image_slug` fields in admin forms.

  Callers pass form field names (e.g. `form[product_variants][0][image_slug]`),
  so on save the stored photo's slug can be merged back into the submitted
  params at that same path. The upload itself is registered under a prefixed
  name: its file input posts an empty value, which would blank the field.

  Files land in `:uploads_dir`, which production mounts inside imgproxy's
  images folder, so the slug is `local:///uploads/<file>`.
  """
  use EdenflowersWeb, :html

  @accept ~w(.jpg .jpeg .png .webp)
  @max_file_size 40_000_000

  def allow(socket, names) do
    socket = Phoenix.Component.assign_new(socket, :photo_slugs, fn -> %{} end)

    Enum.reduce(names, socket, fn name, socket ->
      if socket.assigns[:uploads][upload_name(name)],
        do: socket,
        else:
          Phoenix.LiveView.allow_upload(socket, upload_name(name),
            accept: @accept,
            max_entries: 1,
            max_file_size: @max_file_size
          )
    end)
  end

  @doc "Drops pending and stored photos for `names`, e.g. when removing a form shifts the indexes."
  def forget(socket, names) do
    socket = Phoenix.Component.update(socket, :photo_slugs, &Map.drop(&1, names))

    Enum.reduce(names, socket, fn name, socket ->
      Enum.reduce(socket.assigns.uploads[upload_name(name)].entries, socket, fn entry, socket ->
        Phoenix.LiveView.cancel_upload(socket, upload_name(name), entry.ref)
      end)
    end)
  end

  @doc """
  Stores finished uploads and remembers their slugs, so a save that fails
  validation doesn't lose a photo that's already on disk.
  """
  def store_uploads(socket, names) do
    Enum.reduce(names, socket, fn name, socket ->
      case Phoenix.LiveView.consume_uploaded_entries(socket, upload_name(name), &store/2) do
        [slug] -> Phoenix.Component.update(socket, :photo_slugs, &Map.put(&1, name, slug))
        [] -> socket
      end
    end)
  end

  @doc "Sets each stored photo's slug in `params` at the path its field name describes."
  def merge_slugs(params, socket, names) do
    socket.assigns.photo_slugs
    |> Map.take(names)
    |> Enum.reduce(params, fn {name, slug}, params ->
      deep_merge(params, Plug.Conn.Query.decode(URI.encode_query(%{name => slug}))["form"])
    end)
  end

  defp upload_name(field_name), do: "photo_" <> field_name

  defp store(%{path: path}, entry) do
    dir = Application.fetch_env!(:edenflowers, :uploads_dir)
    filename = file_name(entry.client_name)
    dest = Path.join(dir, filename)

    File.mkdir_p!(dir)
    File.cp!(path, dest)
    # imgproxy runs as another user and answers 500 for files it can't read.
    File.chmod!(dest, 0o644)

    {:ok, "local:///uploads/" <> filename}
  end

  # ASCII only: macOS and the server disagree on how to encode "ä", and a
  # mismatched name 404s. The suffix keeps two "rose.jpg" uploads apart.
  def file_name(client_name) do
    ext = client_name |> Path.extname() |> String.downcase()

    base =
      client_name
      |> Path.rootname()
      |> String.normalize(:nfd)
      |> String.replace(~r/[^A-Za-z0-9]+/u, "-")
      |> String.trim("-")
      |> String.downcase()

    base = if base == "", do: "photo", else: base
    suffix = Base.encode16(:crypto.strong_rand_bytes(3), case: :lower)

    "#{base}-#{suffix}#{ext}"
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      _key, %{} = l, %{} = r -> deep_merge(l, r)
      _key, _l, r -> r
    end)
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :uploads, :map, required: true
  attr :label, :string, required: true
  attr :show_errors, :boolean, default: false
  attr :size, :string, default: "lg", values: ~w(lg sm), doc: "`sm` is a thumbnail for list rows"

  @doc """
  The photo itself is the picker: click it (or drop a file on it) to choose a
  new one. Framed in the store's 4:5 product crop so Jennie sees roughly what
  customers will.
  """
  def photo_input(assigns) do
    upload = assigns.uploads[upload_name(assigns.field.name)]

    assigns =
      assigns
      |> assign(:upload, upload)
      |> assign(:photo, if(is_binary(assigns.field.value) and assigns.field.value != "", do: assigns.field.value))
      |> assign(:upload_errors, Enum.flat_map(upload.entries, &upload_errors(upload, &1)))
      |> assign(:errors, if(assigns.show_errors, do: assigns.field.errors, else: []))

    ~H"""
    <div class={@size == "sm" && "w-16 shrink-0"}>
      <label
        phx-drop-target={@upload.ref}
        class="group outline-primary block cursor-pointer has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2"
      >
        <span class="sr-only">{@label}</span>
        <span class={["bg-cream aspect-[4/5] relative block w-full overflow-hidden", (@errors != [] or @upload_errors != []) && "outline-error outline-1"]}>
          <.live_img_preview
            :for={entry <- @upload.entries}
            entry={entry}
            class="absolute inset-0 h-full w-full object-cover"
          />
          <.image
            :if={@upload.entries == [] and @photo}
            src={@photo}
            alt=""
            width={if @size == "sm", do: 128, else: 640}
            height={if @size == "sm", do: 160, else: 800}
            class="absolute inset-0 h-full w-full object-cover"
          />
          <span
            :if={@upload.entries == [] and is_nil(@photo)}
            class="border-base-content/25 text-cream-content/70 absolute inset-0 flex flex-col items-center justify-center gap-2 border border-dashed transition-colors group-hover:border-base-content/50"
          >
            <.icon name="hero-photo" class={if @size == "sm", do: "size-5", else: "size-8"} />
            <span :if={@size == "lg"} class="px-4 text-center text-sm">{~t"Click or drop a photo here"}</span>
          </span>
        </span>
        <span
          :if={@size == "lg" and (@photo || @upload.entries != [])}
          class="link-underline-static-body mt-2 inline-block text-sm"
        >
          {~t"Replace photo"}
        </span>
        <.live_file_input upload={@upload} class="sr-only" />
      </label>
      <%!-- A thumbnail is too narrow for a sentence; its red outline carries the error, and a
           missing size photo is really the missing product photo, which says so in full. --%>
      <p :for={err <- @upload_errors} class={["text-error mt-1.5 text-sm", @size == "sm" && "sr-only"]}>
        {upload_error_message(err)}
      </p>
      <div :if={@size == "lg"}>
        <.error :for={msg <- Enum.map(@errors, &translate_error/1)}>{msg}</.error>
      </div>
    </div>
    """
  end

  defp upload_error_message(:too_large), do: ~t"The photo is too large (max 40 MB)"
  defp upload_error_message(:not_accepted), do: ~t"Use a JPG, PNG or WebP photo"
  defp upload_error_message(_), do: ~t"The photo could not be uploaded"
end

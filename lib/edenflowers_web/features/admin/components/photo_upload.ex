defmodule EdenflowersWeb.Admin.PhotoUpload do
  @moduledoc """
  Photo uploads for `image_slug` fields in admin forms.

  Callers pass form field names (e.g. `form[image_slug]`),
  so on save the stored photo's slug can be merged back into the submitted
  params at that same path. The upload itself is registered under a prefixed
  name: its file input posts an empty value, which would blank the field.

  Files land in `:uploads_dir`, which production mounts inside imgproxy's
  images folder, so the slug is `local:///uploads/<file>`.
  """
  use EdenflowersWeb, {:html, gettext_domain: "admin"}

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
            max_file_size: @max_file_size,
            auto_upload: true
          )
    end)
  end

  @doc "Allows several photos at once under `name`; `opts` go to `allow_upload/3`, e.g. `progress:`."
  def allow_many(socket, name, opts),
    do: Phoenix.LiveView.allow_upload(socket, name, [accept: @accept, max_file_size: @max_file_size] ++ opts)

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
  validation doesn't lose a photo that's already on disk. A `basename` names
  the file instead of a random one.
  """
  def store_uploads(socket, names, basename \\ nil) do
    Enum.reduce(names, socket, fn name, socket ->
      case Phoenix.LiveView.consume_uploaded_entries(socket, upload_name(name), &store_file(&1, &2, basename)) do
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

  @doc "Copies an upload into `:uploads_dir`; use as a `consume_uploaded_entry` callback."
  def store_file(%{path: path}, entry, basename \\ nil) do
    dir = Application.fetch_env!(:edenflowers, :uploads_dir)
    basename = basename || Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    filename = basename <> String.downcase(Path.extname(entry.client_name))

    dest = Path.join(dir, filename)

    File.mkdir_p!(dir)
    File.cp!(path, dest)
    # imgproxy runs as another user and answers 500 for files it can't read.
    File.chmod!(dest, 0o644)

    {:ok, "local:///uploads/" <> filename}
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

  @doc """
  The photo itself is the picker: click it (or drop a file on it) to choose a
  new one. It uses the product gallery's 4:5 tile and add-photo treatment.
  """
  def photo_input(assigns) do
    upload = assigns.uploads[upload_name(assigns.field.name)]

    assigns =
      assigns
      |> assign(:upload, upload)
      |> assign(:photo, present(assigns.field.value))
      |> assign(:upload_errors, Enum.flat_map(upload.entries, &upload_errors(upload, &1)))
      |> assign(:errors, if(assigns.show_errors, do: assigns.field.errors, else: []))

    ~H"""
    <div class="max-w-60">
      <label
        phx-drop-target={@upload.ref}
        class="group/drop outline-primary block cursor-pointer has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2"
      >
        <span class="sr-only">{@label}</span>
        <span class={["bg-base-200 aspect-[4/5] relative block w-full", (@errors != [] or @upload_errors != []) && "outline-error outline-1"]}>
          <.live_img_preview
            :for={entry <- @upload.entries}
            entry={entry}
            class="absolute inset-0 h-full w-full object-cover"
          />
          <span
            :for={entry <- @upload.entries}
            :if={entry.progress < 100}
            class="bg-base-100/40 absolute inset-0 grid place-items-center"
          >
            <span
              class="radial-progress bg-base-100/80 [--size:3.5rem] text-sm"
              style={"--value:#{entry.progress}"}
              role="progressbar"
              aria-valuenow={entry.progress}
              aria-label={~t"Uploading photo"}
            >
              {entry.progress}%
            </span>
          </span>
          <.image
            :if={@upload.entries == [] and @photo}
            src={@photo}
            alt=""
            width={640}
            height={800}
            class="absolute inset-0 h-full w-full object-cover"
          />
          <span
            :if={@upload.entries == [] and is_nil(@photo)}
            class="border-base-content/20 text-base-content/70 absolute inset-0 flex flex-col items-center justify-center gap-2.5 border border-dashed px-2 text-center transition-colors group-[.phx-drop-target-active]/drop:border-primary group-[.phx-drop-target-active]/drop:bg-primary/5 group-[.phx-drop-target-active]/drop:text-primary group-[.phx-drop-target-active]/drop:border-solid group-hover/drop:border-primary/50 group-hover/drop:bg-primary/5 group-hover/drop:text-primary"
          >
            <span class="bg-base-100 size-9 grid place-items-center rounded-full">
              <.icon name="hero-plus" class="size-4" />
            </span>
            <span class="text-sm font-semibold">{~t"Add photo"}</span>
          </span>
          <span
            :if={@photo || @upload.entries != []}
            aria-hidden="true"
            class="btn btn-sm btn-square pointer-events-none absolute top-1.5 right-1.5 max-sm:btn-xs"
          >
            <.icon name="hero-arrow-path" class="size-3.5 sm:size-4" />
          </span>
        </span>
        <span
          :if={@photo || @upload.entries != []}
          class="link-underline-static-body mt-2 inline-block text-sm"
        >
          {~t"Replace photo"}
        </span>
        <.live_file_input upload={@upload} class="sr-only" />
      </label>
      <p :for={err <- @upload_errors} class="text-error mt-1.5 text-sm">
        {upload_error_message(err)}
      </p>
      <.error :for={msg <- Enum.map(@errors, &translate_error/1)}>{msg}</.error>
    </div>
    """
  end

  defp present(value) when is_binary(value) and value != "", do: value
  defp present(_value), do: nil

  def upload_error_message(:too_large), do: ~t"The photo must be under 40 MB."
  def upload_error_message(:not_accepted), do: ~t"Use a JPG, PNG or WebP photo."
  def upload_error_message(_), do: ~t"Could not upload the photo."
end

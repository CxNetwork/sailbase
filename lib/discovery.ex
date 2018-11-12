defmodule Sailbase.Discovery do
  @kubernetes_master "kubernetes.default.svc"
  @service_account_path "/var/run/secrets/kubernetes.io/serviceaccount"

  def get_nodes(selector, url \\ @kubernetes_master) do
    headers = [{'authorization', 'Bearer #{token()}'}]
    http_options = [ssl: [verify: :verify_none]]
    request = {'https://#{url}/api/v1/namespaces/#{namespace()}/pods?labelSelector=#{selector}', headers}

    response =
      :httpc.request(:get, request, http_options, [])
      |> handle_httpcr()

    case response do
      {:ok, resp} ->
        resp
        |> decode()
        |> parse_api_response()
      {:error, err} when is_list(err) ->
        raise List.to_string(err)
    end
    |> Enum.filter(&pod_healthy?/1)
    |> Enum.map(&pod_details/1)
    |> Enum.map(fn {name, ip} -> :"#{name}@#{ip}" end)
    |> Enum.reject(& &1 == node())
    |> MapSet.new()
  end

  defp handle_httpcr({:ok, resp}), do: handle_httpcresp(resp)
  defp handle_httpcr({:error, err}), do: {:error, [httpc: err]}

  defp handle_httpcresp({{_, status, _}, _, body}), do: handle_httpcs(status, body)

  defp handle_httpcs(200, body), do: {:ok, body}
  defp handle_httpcs(403, body), do: {:error, [unauthorized: decode(body)["message"]]}
  defp handle_httpcs(status, body), do: {:error, [bad_status: status, body: body]}

  defp token(), do: read_service_account_file("token")
  defp namespace(), do: read_service_account_file("namespace")

  defp read_service_account_file(name) do
    path = Path.join(@service_account_path, name)
    if File.exists?(path) do
      path
      |> File.read!()
      |> String.trim()
    else
      raise "No k8s service account file '#{name}'"
    end
  end

  defp decode(body), do: Poison.decode!(body)

  defp parse_api_response(%{"kind" => "PodList", "items" => items}) when is_list(items),
       do: items

  defp pod_healthy?(%{"status" => %{"phase" => "Running", "containerStatuses" => containers}}) do
    count_any = length(containers)

    count_healthy =
      containers
      |> Enum.filter(& container_healthy?/1)
      |> length()

    count_healthy == count_any
  end
  defp pod_healthy?(_), do: false

  defp container_healthy?(%{"state" => %{"running" => _}, "ready" => true}), do: true
  defp container_healthy?(_), do: false

  defp pod_details(%{"status" => %{"podIP" => ip}, "metadata" => %{"name" => name}}),
       do: {name, ip}
end

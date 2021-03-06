defmodule Authex.Verifier do
  alias Authex.Banlist
  alias Authex.Blacklist
  alias Authex.Token
  alias Authex.Signer

  def run(auth, compact_token, opts) do
    signer = Signer.new(auth, opts)
    opts = build_options(auth, opts)

    with {:ok, claims} <- check_token(signer.jwk, signer.jws, compact_token),
         token <- Token.from_map(claims),
         :ok <- check_nbf(opts.time, token.nbf),
         :ok <- check_exp(opts.time, token.exp),
         :ok <- check_blacklist(opts.blacklist, token.jti),
         :ok <- check_banlist(opts.banlist, token.sub) do
      {:ok, token}
    else
      error -> error
    end
  end

  defp check_token(jwk, %{"alg" => alg}, compact) do
    case JOSE.JWT.verify_strict(jwk, [alg], compact) do
      {true, %{fields: claims}, _} -> {:ok, claims}
      {false, _, _} -> {:error, :bad_token}
      {:error, _} -> {:error, :bad_token}
    end
  end

  defp check_nbf(time, nbf) when is_integer(nbf) and time > nbf do
    :ok
  end

  defp check_nbf(_, _) do
    {:error, :not_ready}
  end

  defp check_exp(time, exp) when is_integer(exp) and time < exp do
    :ok
  end

  defp check_exp(_, _) do
    {:error, :expired}
  end

  defp check_blacklist(false, _) do
    :ok
  end

  defp check_blacklist(blacklist, jti) when is_atom(blacklist) and is_binary(jti) do
    case Blacklist.get(blacklist, jti) do
      false -> :ok
      true -> {:error, :blacklisted}
      :error -> {:error, :blacklist_error}
    end
  end

  defp check_blacklist(_, _) do
    {:error, :jti_unverified}
  end

  defp check_banlist(false, _) do
    :ok
  end

  defp check_banlist(banlist, sub) when is_atom(banlist) do
    case Banlist.get(banlist, sub) do
      false -> :ok
      true -> {:error, :banned}
      :error -> {:error, :banlist_error}
    end
  end

  defp check_banlist(_, _) do
    {:error, :sub_unverified}
  end

  defp build_options(auth, opts) do
    Enum.into(opts, %{
      time: :os.system_time(:seconds),
      banlist: auth.config(:banlist, false),
      blacklist: auth.config(:blacklist, false)
    })
  end
end

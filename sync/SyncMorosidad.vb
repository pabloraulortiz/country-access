' Sincroniza morosidad desde SQL Server hacia Supabase (VB.NET Framework 4.8).
' Ejecutar desde un Scheduled Task / servicio cada 15-30 min.
' IMPORTANTE: usar la service_role key SOLO en el servidor, nunca en la app.
Imports System.Data.SqlClient
Imports System.Net.Http
Imports System.Text
Imports Newtonsoft.Json.Linq

Public Module SyncMorosidad

    Private Const SupabaseUrl As String = "https://TU-PROYECTO.supabase.co"
    Private Const ServiceKey As String = "TU_SERVICE_ROLE_KEY"
    Private Const CountryId As String = "UUID-DEL-COUNTRY"

    Public Async Function Ejecutar(connStr As String) As Task
        Dim items As New JArray()

        ' AJUSTAR: consulta de tu sistema. Debe devolver código de lote y si está moroso.
        Const sql As String =
            "SELECT CodigoLote, CASE WHEN SUM(Saldo) > 0 AND MAX(DiasAtraso) > 60 THEN 1 ELSE 0 END AS Moroso " &
            "FROM dbo.vw_DeudaPorLote GROUP BY CodigoLote"

        Using cn As New SqlConnection(connStr)
            cn.Open()
            Using cmd As New SqlCommand(sql, cn)
                Using rd = cmd.ExecuteReader()
                    While rd.Read()
                        items.Add(New JObject From {
                            {"ref", rd.GetString(0).Trim()},
                            {"debt", rd.GetInt32(1) = 1}
                        })
                    End While
                End Using
            End Using
        End Using

        Dim body As New JObject From {{"p_country", CountryId}, {"p_items", items}}

        Using http As New HttpClient()
            http.DefaultRequestHeaders.Add("apikey", ServiceKey)
            http.DefaultRequestHeaders.Add("Authorization", "Bearer " & ServiceKey)
            Dim resp = Await http.PostAsync(SupabaseUrl & "/rest/v1/rpc/sync_lot_debt",
                                            New StringContent(body.ToString(), Encoding.UTF8, "application/json"))
            resp.EnsureSuccessStatusCode()
        End Using
    End Function

End Module

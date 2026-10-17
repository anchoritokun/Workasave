$l = New-Object Net.HttpListener
$l.Prefixes.Add('http://localhost:8765/')
$l.Start()
while ($true) {
  $c = $l.GetContext()
  $name = $c.Request.Url.AbsolutePath.TrimStart('/')
  $path = Join-Path 'C:\Users\ancho.ASUS\AppData\Roaming\Claude\scratch-workspaces\78dd63fc-31cb-4dff-b4b4-abe5177dae72\836b6df0-359f-40e2-a5c8-e92225a14cf6\scratch-2026-10-17-d83a1b\Workasave' $name
  if (Test-Path $path) { $b = [IO.File]::ReadAllBytes($path); $c.Response.OutputStream.Write($b,0,$b.Length) } else { $c.Response.StatusCode = 404 }
  $c.Response.Close()
}

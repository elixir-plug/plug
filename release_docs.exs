# Run with mix run release_docs.exs
Mix.Task.run "docs"
File.rm_rf "../docs/plug"
File.cp_r "docs/.", "../docs/plug/"
File.rm_rf "docs"

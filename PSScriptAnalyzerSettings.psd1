@{
    # Reglas excluidas a proposito (app GUI WinForms sobre PS 5.1):
    #
    # - PSAvoidUsingEmptyCatchBlock: los catch vacios son intencionales en
    #   limpieza de UI / rutas fire-and-forget (dispose de iconos, taskkill,
    #   balloon tips). Fallar ahi no debe tumbar la app.
    # - PSUseShouldProcessForStateChangingFunctions: no aplica a funciones
    #   internas de una app GUI (Start-Download, Stop-Download, etc. no son
    #   cmdlets publicos).
    # - PSAvoidUsingWriteHost: los scripts de build (BuildPortableZip.ps1) son
    #   herramientas interactivas de consola; Write-Host con color es correcto.
    # - PSReviewUnusedParameter: los handlers de eventos WinForms deben aceptar
    #   la firma completa ($sender, $e) aunque no usen ambos parametros.
    # - PSUseDeclaredVarsMoreThanAssignments: falsos positivos conocidos con
    #   variables $script: asignadas en una funcion y leidas en otra (estado
    #   compartido entre handlers de eventos, patron central de esta app).
    ExcludeRules = @(
        'PSAvoidUsingEmptyCatchBlock',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSAvoidUsingWriteHost',
        'PSReviewUnusedParameter',
        'PSUseDeclaredVarsMoreThanAssignments'
    )
}

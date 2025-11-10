#!/bin/bash
# Ejemplos de uso del deploy-via-jumphost.sh con funcionalidad de segundo plano

echo "🚀 Ejemplos de Despliegue en Segundo Plano"
echo "=========================================="
echo ""

echo "1. 📋 Verificar estado de despliegues en segundo plano:"
echo "   ./deploy-via-jumphost.sh --status"
echo ""

echo "2. 🔄 Ejecutar despliegue completo en segundo plano:"
echo "   ./deploy-via-jumphost.sh -b full"
echo ""

echo "3. 👀 Ejecutar despliegue y seguir logs en tiempo real:"
echo "   ./deploy-via-jumphost.sh --follow-logs install-operators"
echo ""

echo "4. 🛑 Detener un despliegue en segundo plano:"
echo "   ./deploy-via-jumphost.sh --stop 12345"
echo ""

echo "5. 🧪 Dry run en segundo plano:"
echo "   ./deploy-via-jumphost.sh -b -d prerequisites"
echo ""

echo "6. 📝 Seguir logs manualmente:"
echo "   tail -f logs/deployment_[lab_id]_[timestamp].log"
echo ""

echo "7. 🔍 Verificar procesos activos:"
echo "   ps aux | grep deploy-via-jumphost"
echo ""

echo "8. 📁 Ver archivos de información de procesos:"
echo "   ls -la pids/"
echo "   cat pids/[PID].info"
echo ""

echo "Flujo de trabajo típico:"
echo "========================"
echo "1. Iniciar despliegue: ./deploy-via-jumphost.sh -b full"
echo "2. Verificar estado:   ./deploy-via-jumphost.sh --status"
echo "3. Seguir logs:        tail -f logs/deployment_*.log"
echo "4. Si necesario:       ./deploy-via-jumphost.sh --stop [PID]"

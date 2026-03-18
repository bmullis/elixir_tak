import { useChannel } from "./hooks/useChannel";
import Layout from "./components/Layout";

export default function App() {
  useChannel();
  return <Layout />;
}
